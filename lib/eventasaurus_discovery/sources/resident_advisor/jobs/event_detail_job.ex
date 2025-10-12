defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for processing individual Resident Advisor events.

  Processes a single transformed event through the unified discovery pipeline.
  This follows the same pattern as Ticketmaster's EventProcessorJob.

  ## Job Arguments

  - `event_data` - Already transformed event data (from SyncJob)
  - `source_id` - Database ID of the RA source
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Sources.ResidentAdvisor
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainers

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
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
        process_event(event_data, source_id, external_id)
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
    case Repo.get(Source, source_id) do
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

  defp get_source_priority(event) do
    case Repo.preload(event, :source) do
      %{source: %{priority: priority}} -> priority
      _ -> "unknown"
    end
  end

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

  defp process_single_event(event_data, _source) do
    # Process the single event through the Processor with scraper name for geocoding metadata
    # Note: We wrap it in a list because Processor.process_source_data expects a list
    case Processor.process_source_data([event_data], "resident_advisor") do
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
