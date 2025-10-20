defmodule EventasaurusDiscovery.Sources.Quizmeisters.Jobs.VenueDetailJob do
  @moduledoc """
  Scrapes individual venue detail pages, processes performer data, and creates events.

  ## Workflow
  1. Fetch venue detail page HTML
  2. Extract additional venue details (website, phone, description, hero_image, etc.)
  3. Extract performer data (name + image_url stored as string)
  4. Parse time_text to generate next event occurrence
  5. Transform to unified format with performer info
  6. Process through Processor.process_source_data/2
  7. Link performer to event via PublicEventPerformer

  ## Critical Features
  - Uses Processor.process_source_data/2 (NOT manual VenueStore/EventStore)
  - GPS coordinates already provided (no geocoding needed)
  - Performer handled via PerformerStore.find_or_create_performer/1
  - EventProcessor updates last_seen_at timestamp
  - Stable external_ids for deduplication
  - Weekly recurring events with metadata
  - Performer image URLs stored as strings (no download/upload)

  ## Performer Handling
  - Extract from .host-info HTML elements
  - Store image_url as string (no download/upload)
  - Default fallback: "Quizmeisters Host"
  - Fuzzy matching with Jaro distance ≥0.85
  - Linked via PublicEventPerformer join table
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.Quizmeisters.{
    Extractors.VenueDetailsExtractor,
    Transformer
  }

  alias EventasaurusDiscovery.Sources.Shared.RecurringEventParser

  alias EventasaurusDiscovery.Sources.Processor
  alias EventasaurusDiscovery.Performers.PerformerStore
  alias EventasaurusDiscovery.PublicEvents.PublicEventPerformer
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id} = job) do
    venue_id = args["venue_id"]
    venue_url = args["venue_url"]
    venue_name = args["venue_name"]
    venue_data = string_keys_to_atoms(args["venue_data"])
    source_id = args["source_id"]

    # Use venue_url as external_id for metrics tracking, fallback to job.id
    # Ensures external_id is always a string
    external_id = to_string(venue_url || job_id)

    Logger.info("🔍 Processing Quizmeisters venue: #{venue_name} (ID: #{venue_id})")

    result =
      with {:ok, additional_details} <- fetch_additional_details(venue_url),
           {:ok, {day_of_week, time}} <- parse_time_text(venue_data.time_text),
           {:ok, next_occurrence} <- calculate_next_occurrence(day_of_week, time),
           {:ok, performer} <- process_performer(additional_details[:performer], source_id),
           enriched_venue_data <-
             enrich_venue_data(venue_data, additional_details, next_occurrence),
           {:ok, transformed} <- transform_and_validate(enriched_venue_data),
           {:ok, events} <- process_event(transformed, source_id),
           :ok <- link_performer_to_events(performer, events) do
        Logger.info("✅ Successfully processed venue: #{venue_name}")
        log_results(events, performer)
        {:ok, %{events: length(events), performer: performer != nil}}
      else
        {:error, reason} = error ->
          Logger.error("❌ Failed to process venue #{venue_url}: #{inspect(reason)}")
          error
      end

    # Track metrics in job metadata
    case result do
      {:ok, _} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result

      _other ->
        result
    end
  end

  # Convert string keys to atoms for venue_data map
  defp string_keys_to_atoms(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp fetch_additional_details(venue_url) do
    case VenueDetailsExtractor.extract_additional_details(venue_url) do
      {:ok, details} ->
        {:ok, details}

      {:error, reason} ->
        Logger.warning("⚠️ Failed to fetch additional details, using defaults: #{inspect(reason)}")
        # Return empty map as fallback - transformer will handle missing fields
        {:ok, %{}}
    end
  end

  defp parse_time_text(nil), do: {:error, "Missing time_text"}

  defp parse_time_text(time_text) do
    with {:ok, day} <- RecurringEventParser.parse_day_of_week(time_text),
         {:ok, time} <- RecurringEventParser.parse_time(time_text) do
      {:ok, {day, time}}
    else
      {:error, reason} ->
        Logger.warning("⚠️ Failed to parse time_text '#{time_text}': #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp calculate_next_occurrence(day_of_week, time) do
    # Calculate next occurrence in Australia/Sydney timezone
    next_dt = RecurringEventParser.next_occurrence(day_of_week, time, "Australia/Sydney")
    {:ok, next_dt}
  rescue
    error ->
      Logger.error("❌ Failed to calculate next occurrence: #{inspect(error)}")
      {:error, "Failed to calculate next occurrence"}
  end

  # Process performer data through PerformerStore
  defp process_performer(nil, _source_id) do
    Logger.debug("ℹ️ No performer data available")
    {:ok, nil}
  end

  defp process_performer(performer_data, source_id) do
    attrs = %{
      name: performer_data.name,
      image_url: performer_data.image_url,
      source_id: source_id,
      metadata: %{
        source: "quizmeisters"
      }
    }

    case PerformerStore.find_or_create_performer(attrs) do
      {:ok, performer} ->
        Logger.info("✅ Processed performer: #{performer.name} (ID: #{performer.id})")
        {:ok, performer}

      {:error, reason} ->
        Logger.error("❌ Failed to process performer: #{inspect(reason)}")
        # Don't fail the entire job for performer issues
        {:ok, nil}
    end
  end

  # Enrich venue data with additional details and event occurrence
  defp enrich_venue_data(venue_data, additional_details, next_occurrence) do
    venue_data
    |> Map.merge(additional_details)
    |> Map.put(:starts_at, next_occurrence)
  end

  defp transform_and_validate(venue_data) do
    case Transformer.transform_event(venue_data) do
      transformed when is_map(transformed) ->
        {:ok, transformed}

      _ ->
        {:error, "Transformation failed"}
    end
  end

  # CRITICAL: Use Processor.process_source_data/3
  # This handles:
  # - VenueProcessor (no geocoding needed - GPS provided)
  # - EventProcessor creation/update
  # - last_seen_at timestamps
  # - Deduplication via external_id
  # - Scraper attribution via explicit scraper name
  defp process_event(transformed, source_id) do
    case Processor.process_source_data([transformed], source_id, "quizmeisters") do
      {:ok, events} -> {:ok, events}
      error -> error
    end
  end

  # Link performer to events via PublicEventPerformer join table
  defp link_performer_to_events(nil, _events), do: :ok

  defp link_performer_to_events(performer, events) do
    events
    |> Enum.each(fn event ->
      case link_performer_to_event(performer, event) do
        {:ok, _} ->
          Logger.debug("🔗 Linked performer #{performer.id} to event #{event.id}")

        {:error, reason} ->
          Logger.warning("⚠️ Failed to link performer to event: #{inspect(reason)}")
      end
    end)

    :ok
  end

  defp link_performer_to_event(performer, event) do
    # Use PublicEventPerformer join table
    attrs = %{
      event_id: event.id,
      performer_id: performer.id
    }

    # Upsert to avoid duplicates
    %PublicEventPerformer{}
    |> PublicEventPerformer.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:event_id, :performer_id]
    )
  end

  defp log_results(events, performer) do
    count = length(events)
    performer_info = if performer, do: " with performer: #{performer.name}", else: ""

    Logger.info("""
    📊 Processing results:
    - Events processed: #{count}#{performer_info}
    """)
  end
end
