defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.DetailJob do
  @moduledoc """
  Oban job for fetching and processing individual Speed Quizzing event details.

  ## Workflow
  1. Fetch event detail page HTML
  2. Extract venue and event data using VenueExtractor
  3. Parse date/time using shared DateParser
  4. Transform to unified format via Transformer
  5. Process through Processor.process_source_data/3
  6. Handle performer data and image downloads
  7. Link performer to event

  ## Critical Features
  - Uses Processor.process_source_data/3 (NOT manual VenueStore/EventStore)
  - GPS coordinates in detail page (no geocoding needed)
  - Performer image URLs downloaded and uploaded
  - EventProcessor updates last_seen_at timestamp
  - Stable external_ids for deduplication
  - Weekly recurring events with metadata
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.SpeedQuizzing.{
    Client,
    Extractors.VenueExtractor,
    Transformer
  }

  alias EventasaurusDiscovery.Sources.Processor
  alias EventasaurusDiscovery.Performers.PerformerStore
  alias EventasaurusDiscovery.PublicEvents.PublicEventPerformer
  alias EventasaurusApp.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source_id = args["source_id"]
    event_id = args["event_id"]
    event_data = args["event_data"]

    Logger.info("🔍 Processing Speed Quizzing event: #{event_id}")

    with {:ok, html} <- Client.fetch_event_details(event_id),
         {:ok, document} <- parse_html(html),
         venue_data <- VenueExtractor.extract(document, event_id),
         venue_data <- merge_event_data(venue_data, event_data),
         {:ok, performer} <- process_performer(venue_data.performer, source_id),
         {:ok, transformed} <- transform_and_validate(venue_data, source_id),
         {:ok, events} <- process_event(transformed, source_id),
         :ok <- link_performer_to_events(performer, events) do
      Logger.info("✅ Successfully processed event: #{event_id}")
      log_results(events, performer)
      {:ok, %{events: length(events), performer: performer != nil}}
    else
      {:error, reason} = error ->
        Logger.error("❌ Failed to process event #{event_id}: #{inspect(reason)}")
        error
    end
  end

  # Parse HTML document with Floki
  defp parse_html(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        {:ok, document}

      {:error, reason} ->
        Logger.error("❌ Failed to parse HTML: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  # Merge data from index job with extracted detail data
  defp merge_event_data(venue_data, event_data) when is_map(event_data) do
    # Use index data as fallback if detail extraction failed
    # CRITICAL: Speed Quizzing removed GPS from detail pages - use index data instead
    # Convert GPS coordinates to string format (they come as floats from index JSON)
    lat = if event_data["lat"], do: to_string(event_data["lat"]), else: nil
    lon = if event_data["lon"], do: to_string(event_data["lon"]), else: nil

    venue_data
    |> maybe_replace_unknown(:start_time, event_data["start_time"])
    |> maybe_replace_unknown(:day_of_week, event_data["day_of_week"])
    |> maybe_replace_unknown(:date, event_data["date"])
    |> maybe_replace_unknown(:lat, lat)
    |> maybe_replace_unknown(:lng, lon)
    |> maybe_replace_empty(:lat, lat)
    |> maybe_replace_empty(:lng, lon)
  end

  defp merge_event_data(venue_data, _), do: venue_data

  defp maybe_replace_unknown(data, _field, nil), do: data

  defp maybe_replace_unknown(data, field, value) do
    case Map.get(data, field) do
      "Unknown" -> Map.put(data, field, value)
      "" -> Map.put(data, field, value)
      _ -> data
    end
  end

  defp maybe_replace_empty(data, _field, nil), do: data

  defp maybe_replace_empty(data, field, value) do
    case Map.get(data, field) do
      "" -> Map.put(data, field, value)
      nil -> Map.put(data, field, value)
      _ -> data
    end
  end

  # Process performer data through PerformerStore
  defp process_performer(nil, _source_id) do
    Logger.debug("ℹ️ No performer data available")
    {:ok, nil}
  end

  defp process_performer(performer_data, source_id) when is_map(performer_data) do
    attrs = %{
      name: performer_data.name,
      image_url: performer_data.profile_image,
      source_id: source_id,
      metadata: %{
        source: "speed-quizzing",
        description: performer_data[:description]
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

  defp transform_and_validate(venue_data, source_id) do
    case Transformer.transform_event(venue_data, source_id) do
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
    case Processor.process_source_data([transformed], source_id, "speed-quizzing") do
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
