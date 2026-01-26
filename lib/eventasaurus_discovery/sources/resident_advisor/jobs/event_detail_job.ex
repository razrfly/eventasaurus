defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for processing individual Resident Advisor events.

  Processes a single transformed event through the unified discovery pipeline.
  This follows the same pattern as Ticketmaster's EventProcessorJob.

  ## Job Arguments

  - `event_data` - Already transformed event data (from SyncJob)
  - `source_id` - Database ID of the RA source
  """

  # Job timeout of 60 seconds to prevent connection pool exhaustion
  # RA events are simpler than restaurant slots, should complete in ~30s
  @job_timeout_ms 60_000

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Sources.ResidentAdvisor
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainers
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    event_data = args["event_data"] || %{}
    source_id = args["source_id"]
    external_id = Map.get(event_data, "external_id") || Map.get(event_data, :external_id)

    # CRITICAL: Guard against nil identifiers before marking as seen
    # Prevents bogus "seen" records if job payload is malformed
    cond do
      is_nil(source_id) ->
        Logger.error("🚫 Discarding RA event: missing source_id in args")
        {:discard, :missing_source_id}

      is_nil(external_id) ->
        Logger.error("🚫 Discarding RA event for source #{source_id}: missing external_id")
        {:discard, :missing_external_id}

      true ->
        # CRITICAL: Mark event as seen BEFORE processing
        # This ensures last_seen_at is updated even if processing fails
        EventProcessor.mark_event_as_seen(external_id, source_id)

        # Process event with timeout to prevent connection pool exhaustion
        result = execute_with_timeout(event_data, source_id, external_id)

        case result do
          {:ok, _} ->
            MetricsTracker.record_success(job, external_id)
            result

          {:discard, reason} ->
            MetricsTracker.record_failure(job, reason, external_id)
            result

          {:error, reason} ->
            MetricsTracker.record_failure(job, reason, external_id)
            result
        end
    end
  end

  # Execute with timeout to prevent connection pool exhaustion
  defp execute_with_timeout(event_data, source_id, external_id) do
    task = Task.async(fn -> process_event(event_data, source_id, external_id) end)

    case Task.yield(task, @job_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        Logger.warning(
          "[RA.EventDetailJob] ⏰ Timeout after #{div(@job_timeout_ms, 1000)}s for #{external_id}"
        )

        {:error, :timeout}

      {:exit, reason} ->
        Logger.error(
          "[RA.EventDetailJob] 💥 Task crashed for #{external_id} " <>
            "(timeout: #{div(@job_timeout_ms, 1000)}s): #{inspect(reason)}"
        )

        {:error, {:exit, reason}}
    end
  end

  defp process_event(event_data, source_id, external_id) do
    Logger.info("🎵 Processing RA event: #{external_id}")

    # Get the source
    with {:ok, source} <- get_source(source_id),
         # Check for duplicates from higher-priority sources (pass source struct)
         {:ok, dedup_result} <- check_deduplication(event_data, source),
         # Process the event if unique
         {:ok, processed_event} <- process_event_if_unique(event_data, source, dedup_result) do
      Logger.info("✅ Successfully processed RA event: #{external_id}")

      # Check for prospective container associations
      # This allows sub-events imported before umbrella to be associated retroactively
      if processed_event != :skipped_duplicate do
        PublicEventContainers.check_for_container_match(processed_event)
      end

      {:ok, %{event_id: external_id, status: "processed"}}
    else
      {:error, :source_not_found} ->
        Logger.error("🚫 Discarding event #{external_id}: source #{source_id} not found")
        {:discard, :source_not_found}

      {:error, {:discard, reason}} ->
        # Critical failure (e.g., missing GPS coordinates) - discard the job
        Logger.error("🚫 Discarding event #{external_id}: #{reason}")
        {:discard, reason}

      {:error, reason} ->
        # Regular error - allow retry
        Logger.error("❌ Failed to process event #{external_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_source(source_id) do
    case JobRepo.get(Source, source_id) do
      nil -> {:error, :source_not_found}
      source -> {:ok, source}
    end
  end

  defp check_deduplication(event_data, source) do
    # Convert string keys to atom keys for dedup handler
    event_with_atom_keys = atomize_event_data(event_data)

    case ResidentAdvisor.deduplicate_event(event_with_atom_keys, source) do
      {:unique, _} ->
        {:ok, :unique}

      {:duplicate, existing} ->
        Logger.info("""
        ⏭️  Skipping duplicate event from higher-priority source
        RA: #{event_data["title"] || event_data[:title]}
        Existing: #{existing.title} (source priority: #{get_source_priority(existing)})
        """)

        {:ok, :skip_duplicate}

      {:enriched, enriched_data} ->
        Logger.info("✨ RA event can enrich existing event")
        {:ok, {:enriched, enriched_data}}

      {:container, _container} ->
        # Event was created as a container (umbrella event)
        Logger.info("🎪 Event created as container (umbrella event)")
        {:ok, :container_created}

      {:error, reason} ->
        Logger.warning("⚠️ Deduplication validation failed: #{inspect(reason)}")
        # Continue with processing even if dedup fails
        {:ok, :validation_failed}
    end
  end

  defp atomize_event_data(%{} = data) do
    Enum.reduce(data, %{}, fn {k, v}, acc ->
      key =
        if is_binary(k) do
          try do
            String.to_existing_atom(k)
          rescue
            ArgumentError -> k
          end
        else
          k
        end

      Map.put(acc, key, atomize_event_data(v))
    end)
  end

  defp atomize_event_data(list) when is_list(list) do
    Enum.map(list, &atomize_event_data/1)
  end

  defp atomize_event_data(value), do: value

  # Look up source priority via PublicEventSource join table
  # The Event schema doesn't have a :source association - the priority lives in
  # Source, which is linked through PublicEventSource
  defp get_source_priority(%{id: event_id}) when not is_nil(event_id) do
    import Ecto.Query
    alias EventasaurusDiscovery.PublicEvents.PublicEventSource

    query =
      from(pes in PublicEventSource,
        join: s in Source,
        on: s.id == pes.source_id,
        where: pes.event_id == ^event_id,
        select: s.priority,
        limit: 1
      )

    case JobRepo.one(query) do
      nil -> "unknown"
      priority -> priority
    end
  end

  defp get_source_priority(_), do: "unknown"

  defp process_event_if_unique(event_data, source, dedup_result) do
    case dedup_result do
      :unique ->
        process_single_event(event_data, source)

      :skip_duplicate ->
        {:ok, :skipped_duplicate}

      {:enriched, _enriched_data} ->
        # TODO: Implement enrichment logic
        # For now, skip the event since it already exists
        {:ok, :skipped_duplicate}

      :container_created ->
        # Container was already created, don't process as regular event
        {:ok, :skipped_duplicate}

      :validation_failed ->
        # Process anyway if validation failed
        process_single_event(event_data, source)
    end
  end

  defp process_single_event(event_data, source) do
    # Process the single event through the Processor
    # Note: We wrap it in a list because Processor.process_source_data expects a list
    # Pass explicit scraper name for venue attribution metadata
    case Processor.process_source_data([event_data], source, "resident_advisor") do
      {:ok, [processed_event]} ->
        {:ok, processed_event}

      {:ok, []} ->
        {:error, {:discard, :event_rejected_by_processor}}

      {:discard, reason} ->
        # Processor returned discard (e.g., missing GPS coordinates)
        {:error, {:discard, reason}}

      {:error, {:partial_failure, failed, total}} ->
        # Single event failed processing
        Logger.warning("Event processing failed (partial_failure: #{failed}/#{total})")
        {:error, :event_processing_failed}

      {:error, reason} ->
        {:error, reason}

      other ->
        Logger.warning("Unexpected result from Processor: #{inspect(other)}")
        {:error, :unexpected_processor_result}
    end
  end
end
