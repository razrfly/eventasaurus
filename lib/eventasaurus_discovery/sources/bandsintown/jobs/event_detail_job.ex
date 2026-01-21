defmodule EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for processing individual Bandsintown event details.

  This job processes a single event through the unified Processor,
  maintaining venue validation requirements while providing:
  - Retry capability per event
  - Parallel processing
  - Failure isolation

  Each EventDetailJob:
  1. Receives event data from IndexPageJob
  2. Transforms the event using Bandsintown.Transformer
  3. Processes through the unified Processor for venue validation
  4. Creates or updates the event in the database

  This restores the async functionality that was removed in commit d42309da
  while maintaining the venue validation requirements that were added.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.Bandsintown
  alias EventasaurusDiscovery.Sources.Bandsintown.{Client, DetailExtractor, Transformer}
  alias EventasaurusDiscovery.Sources.Processor
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    event_data = args["event_data"]
    source_id = args["source_id"]
    city_id = args["city_id"]
    external_id = args["external_id"]
    from_page = args["from_page"]

    # CRITICAL: Mark event as seen BEFORE processing
    # This ensures last_seen_at is updated even if processing fails
    EventProcessor.mark_event_as_seen(external_id, source_id)

    Logger.debug("""
    🎵 Processing Bandsintown event
    External ID: #{external_id}
    From page: #{from_page}
    Artist: #{event_data["artist_name"]}
    Venue: #{event_data["venue_name"]}
    """)

    # Get source and city
    result =
      with {:ok, source} <- get_source(source_id),
           {:ok, city} <- get_city(city_id),
           # Fetch event detail page to get GPS coordinates from JSON-LD
           enriched_event_data <- enrich_with_detail_page(event_data),
           # Transform the event data with city context for proper venue association
           {:ok, transformed_event} <- transform_event(enriched_event_data, city),
           # Check for duplicates from higher-priority sources (pass source struct)
           {:ok, dedup_result} <- check_deduplication(transformed_event, source),
           # Process through unified Processor for venue validation
           {:ok, result} <- process_event_if_unique(transformed_event, source, dedup_result) do
        case result do
          event when is_struct(event) ->
            # Successfully processed and created/updated event
            {:ok, event}

          :skipped_duplicate ->
            # Event was skipped due to deduplication
            {:ok, :skipped_duplicate}

          :filtered ->
            # Event was filtered out during processing
            {:ok, :filtered}

          :discarded ->
            # Event was discarded (e.g., missing GPS coordinates)
            {:ok, :discarded}

          other ->
            Logger.warning("⚠️ Unexpected processing result: #{inspect(other)}")
            {:ok, other}
        end
      else
        {:error, :source_not_found} ->
          Logger.error("❌ Source not found: #{source_id}")
          {:error, :source_not_found}

        {:error, :city_not_found} ->
          Logger.error("❌ City not found: #{city_id}")
          {:error, :city_not_found}

        {:error, reason} ->
          Logger.error("❌ Failed to process event: #{inspect(reason)}")
          {:error, reason}
      end

    # Track metrics in job metadata
    case result do
      {:ok, _} ->
        MetricsTracker.record_success(job, external_id)
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

  defp get_city(city_id) do
    case JobRepo.get(City, city_id) |> JobRepo.preload(:country) do
      nil -> {:error, :city_not_found}
      city -> {:ok, city}
    end
  end

  defp enrich_with_detail_page(event_data) do
    # If we have a URL, fetch the detail page to get GPS coordinates from JSON-LD
    case event_data["url"] do
      nil ->
        Logger.warning("⚠️ No URL for event, cannot fetch detail page")
        event_data

      url when is_binary(url) and url != "" ->
        Logger.debug("🌐 Fetching event detail page: #{url}")

        case Client.fetch_event_page(url) do
          {:ok, html} ->
            # Extract details from the HTML page, including JSON-LD with GPS
            case DetailExtractor.extract_event_details(html, url) do
              {:ok, detail_data} ->
                # Merge the detail page data with the API data
                # Detail page data takes precedence for GPS coordinates
                merged_data = Map.merge(event_data, detail_data)

                if detail_data["venue_latitude"] && detail_data["venue_longitude"] do
                  Logger.info("""
                  📍 Extracted GPS coordinates from detail page:
                  Venue: #{merged_data["venue_name"]}
                  Lat: #{detail_data["venue_latitude"]}
                  Lng: #{detail_data["venue_longitude"]}
                  """)
                else
                  Logger.warning("⚠️ No GPS coordinates found in detail page JSON-LD")
                end

                merged_data

              {:error, reason} ->
                Logger.warning("⚠️ Failed to extract details from page: #{inspect(reason)}")
                event_data
            end

          {:error, reason} ->
            Logger.warning("⚠️ Failed to fetch detail page: #{inspect(reason)}")
            event_data
        end

      _ ->
        Logger.warning("⚠️ Invalid URL for event")
        event_data
    end
  end

  defp transform_event(event_data, city) do
    # Use the Transformer to convert the event data
    # The event_data already has string keys from IndexPageJob
    # Pass the city context for proper venue association
    case Transformer.transform_event(event_data, city) do
      {:ok, event} ->
        Logger.debug("✅ Event transformed successfully")
        {:ok, event}

      {:error, reason} ->
        Logger.warning("⚠️ Failed to transform event: #{inspect(reason)}")
        {:error, {:transform_failed, reason}}
    end
  end

  defp check_deduplication(event, source) do
    case Bandsintown.deduplicate_event(event, source) do
      {:unique, _} ->
        {:ok, :unique}

      {:duplicate, existing} ->
        Logger.info("""
        ⏭️  Skipping duplicate concert from higher-priority source
        Bandsintown: #{event[:title]}
        Existing: #{existing.title} (source priority: #{get_source_priority(existing)})
        """)

        {:ok, :skip_duplicate}

      {:error, reason} ->
        Logger.warning("⚠️ Deduplication validation failed: #{inspect(reason)}")
        # Continue with processing even if dedup fails
        {:ok, :validation_failed}
    end
  end

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

  defp process_event_if_unique(event, source, dedup_result) do
    case dedup_result do
      :unique ->
        process_event(event, source)

      :skip_duplicate ->
        {:ok, :skipped_duplicate}

      :validation_failed ->
        # Process anyway if validation failed
        process_event(event, source)
    end
  end

  defp process_event(event, source) do
    # Process through the unified Processor
    # This maintains the venue validation requirements from commit d42309da
    # The Processor expects a list of events
    events_to_process = [event]

    Logger.debug("🔄 Processing event through unified Processor")

    # Call the Processor with the required arguments
    # The Processor will handle venue validation and event creation/updating
    # Note: City is not needed by the Processor, it uses venue data from the event
    # Pass explicit scraper name for venue attribution metadata
    case Processor.process_source_data(events_to_process, source, "bandsintown") do
      {:ok, results} when is_list(results) ->
        # process_source_data returns a list of processed events
        Logger.debug("✅ Event processed through Processor")

        case results do
          [processed_event | _] ->
            Logger.info("""
            ✅ Event processed successfully
            Title: #{processed_event.title}
            Venue: #{if processed_event.venue, do: processed_event.venue.name, else: "Unknown"}
            """)

            {:ok, processed_event}

          [] ->
            Logger.warning("⚠️ Event was filtered out during processing")
            {:ok, :filtered}
        end

      {:error, reason} ->
        Logger.error("❌ Processor failed: #{inspect(reason)}")
        {:error, {:processor_failed, reason}}

      {:discard, reason} ->
        Logger.warning("⚠️ Event discarded: #{inspect(reason)}")
        {:ok, :discarded}
    end
  rescue
    error ->
      Logger.error("""
      ❌ Exception during event processing:
      #{inspect(error)}
      #{inspect(__STACKTRACE__)}
      """)

      {:error, {:exception, error}}
  end
end
