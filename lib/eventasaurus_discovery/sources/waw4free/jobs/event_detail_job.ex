defmodule EventasaurusDiscovery.Sources.Waw4free.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for processing individual Waw4Free event details.

  Phase 1 PLACEHOLDER: Basic structure only.
  Phase 3 TODO: Implement event detail page scraping logic.

  This job will:
  1. Fetch the event detail page HTML
  2. Extract all event fields (title, date, time, venue, description, image, etc.)
  3. Parse Polish date format
  4. Apply category mapping
  5. Transform to unified event format
  6. Process through unified pipeline (VenueProcessor, EventProcessor)
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Sources.Waw4free.{Config, Client, DetailExtractor, Transformer}
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    # Clean the data that comes from job storage
    clean_args = EventasaurusDiscovery.Utils.UTF8.validate_map_strings(args)
    url = clean_args["url"]
    source_id = clean_args["source_id"]
    event_metadata = clean_args["event_metadata"] || %{}
    external_id = clean_args["external_id"] || Config.extract_external_id(url)

    # CRITICAL: Add external_id to event_metadata (BandsInTown A+ pattern)
    event_metadata_with_id = Map.put(event_metadata, :external_id, external_id)

    # CRITICAL: Mark event as seen BEFORE processing
    EventProcessor.mark_event_as_seen(external_id, source_id)

    Logger.info("🎉 Processing Waw4free event: #{url} (External ID: #{external_id})")

    # Get source from database
    source = JobRepo.get!(Source, source_id)

    # Process the event
    result = process_event(url, source, event_metadata_with_id)

    # Track metrics
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

      _other ->
        result
    end
  end

  # Private helper functions

  defp process_event(url, source, event_metadata) do
    with {:ok, html} <- fetch_event_page(url),
         {:ok, event_data} <- extract_event_details(html, url, event_metadata),
         {:ok, transformed} <- transform_event(event_data),
         {:ok, result} <- process_through_pipeline(transformed, source) do
      Logger.info("✅ Successfully processed event: #{event_data[:title]}")
      {:ok, result}
    else
      {:error, :not_found} ->
        Logger.warning("Event page not found: #{url}")
        {:discard, :not_found}

      {:error, :invalid_data} ->
        Logger.warning("Invalid event data for: #{url}")
        {:discard, :invalid_data}

      {:error, :no_venue} ->
        Logger.warning("Event has no venue: #{url}")
        {:discard, :no_venue}

      {:error, reason} = error ->
        Logger.error("Failed to process event #{url}: #{inspect(reason)}")
        error
    end
  end

  defp fetch_event_page(url) do
    Logger.debug("📥 Fetching event page: #{url}")

    case Client.fetch_page(url) do
      {:ok, html} ->
        # DEBUG: Save HTML to file for comparison
        external_id = url |> String.split("/") |> List.last()
        File.write("/tmp/waw4free_#{external_id}.html", html)
        Logger.debug("💾 Saved HTML to /tmp/waw4free_#{external_id}.html")
        {:ok, html}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Failed to fetch page #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_event_details(html, url, event_metadata) do
    Logger.debug("🔍 Extracting event details from: #{url}")

    case DetailExtractor.extract_event_from_html(html, url) do
      {:ok, event_data} ->
        # Merge with metadata from index page
        merged_data =
          Map.merge(event_data, %{
            metadata: event_metadata
          })

        {:ok, merged_data}

      {:error, reason} ->
        Logger.error("Failed to extract event details from #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp transform_event(event_data) do
    Logger.debug("🔄 Transforming event: #{event_data[:title]}")

    case Transformer.transform_event(event_data) do
      {:ok, transformed} ->
        {:ok, transformed}

      {:error, reason} ->
        Logger.error("Failed to transform event #{event_data[:title]}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_through_pipeline(transformed_event, source) do
    Logger.debug("⚙️ Processing through unified pipeline: #{transformed_event[:title]}")

    # Use the unified Processor which handles:
    # 1. Venue geocoding and creation
    # 2. Event creation/update
    # 3. Category assignment
    # 4. Image processing
    case Processor.process_single_event(transformed_event, source, "waw4free") do
      {:ok, result} ->
        {:ok, result}

      {:error, {:discard, reason}} ->
        # Critical failure (e.g., missing GPS coordinates)
        Logger.error("Critical failure for event #{transformed_event[:title]}: #{reason}")
        {:discard, reason}

      {:error, reason} ->
        Logger.error("""
        Failed to process event through pipeline:
        Event: #{transformed_event[:title]}
        Reason: #{inspect(reason)}
        """)

        {:error, reason}
    end
  end
end
