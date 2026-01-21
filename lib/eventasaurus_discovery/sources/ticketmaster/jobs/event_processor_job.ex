defmodule EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob do
  @moduledoc """
  Oban job for processing individual Ticketmaster event details.

  Processes a single transformed event through the unified discovery pipeline.
  This follows the same pattern as Karnet's EventDetailJob but for Ticketmaster events
  that have already been transformed.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Sources.Ticketmaster
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Utils.ObanHelpers
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # Override to truncate args in Oban Web display
  def __meta__(:display_args) do
    fn args -> ObanHelpers.truncate_job_args(args) end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    # Clean UTF-8 from potentially corrupted job args stored in DB
    # This handles jobs that were stored with bad UTF-8 before our fixes
    clean_args = EventasaurusDiscovery.Utils.UTF8.validate_map_strings(args)

    event_data = clean_args["event_data"] || %{}
    source_id = clean_args["source_id"]
    external_id = Map.get(event_data, "external_id") || Map.get(event_data, :external_id)

    # CRITICAL: Mark event as seen BEFORE processing
    # This ensures last_seen_at is updated even if processing fails
    EventProcessor.mark_event_as_seen(external_id, source_id)

    Logger.info("🎫 Processing Ticketmaster event: #{external_id}")

    # Get the source
    result =
      with {:ok, source} <- get_source(source_id),
           # Check for duplicates (within Ticketmaster itself, pass source struct)
           {:ok, dedup_result} <- check_deduplication(event_data, source),
           # Process the event if unique
           {:ok, _processed_event} <- process_event_if_unique(event_data, source, dedup_result) do
        Logger.info("✅ Successfully processed Ticketmaster event: #{external_id}")
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
          truncated_args = ObanHelpers.truncate_job_args(args)
          Logger.error("❌ Failed to process event #{external_id}: #{inspect(reason)}")
          Logger.debug("Truncated job args: #{inspect(truncated_args)}")
          {:error, reason}
      end

    # Track metrics in job metadata
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

  defp get_source(source_id) do
    case JobRepo.get(Source, source_id) do
      nil -> {:error, :source_not_found}
      source -> {:ok, source}
    end
  end

  defp check_deduplication(event_data, source) do
    # Convert string keys to atom keys for dedup handler
    event_with_atom_keys = atomize_event_data(event_data)

    case Ticketmaster.deduplicate_event(event_with_atom_keys, source) do
      {:unique, _} ->
        {:ok, :unique}

      {:duplicate, existing} ->
        Logger.info("""
        ⏭️  Skipping duplicate Ticketmaster event
        New: #{event_data["title"] || event_data[:title]}
        Existing: #{existing.title} (ID: #{existing.id})
        """)

        {:ok, :skip_duplicate}

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

  defp process_event_if_unique(event_data, source, dedup_result) do
    case dedup_result do
      :unique ->
        process_single_event(event_data, source)

      :skip_duplicate ->
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
    case Processor.process_source_data([event_data], source, "ticketmaster") do
      {:ok, [processed_event]} ->
        {:ok, processed_event}

      {:ok, []} ->
        # Empty result means the event failed to process - this is an ERROR!
        Logger.error("Event processing returned empty result - processing failed")
        {:error, :event_processing_failed}

      {:error, {:all_events_failed, error_details}} ->
        # The single event failed to process
        Logger.error("Event processing failed: #{inspect(error_details)}")
        {:error, :event_processing_failed}

      {:error, {:partial_failure, _, _}} ->
        # Single event can't have partial failure, this means it failed
        Logger.error("Event processing failed (unexpected partial failure for single event)")
        {:error, :event_processing_failed}

      {:discard, reason} ->
        # Critical failure that should discard the job
        {:discard, reason}

      {:error, reason} ->
        # Other errors should be retried
        Logger.error("Event processing failed: #{inspect(reason)}")
        {:error, reason}

      other ->
        # Catch any other unexpected return value
        Logger.warning("Unexpected return from Processor: #{inspect(other)}")
        {:error, :unexpected_processor_response}
    end
  end
end
