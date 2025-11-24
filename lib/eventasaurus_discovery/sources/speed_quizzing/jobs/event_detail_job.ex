defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for fetching and processing individual Speed Quizzing event details with host data in metadata.

  ## Workflow
  1. Fetch event detail page HTML
  2. Extract venue, event, and host data using VenueExtractor
  3. Parse date/time using shared DateParser
  4. Transform to unified format with host in description + metadata
  5. Process through Processor.process_source_data/3

  ## Critical Features
  - Uses Processor.process_source_data/3 (NOT manual VenueStore/EventStore)
  - GPS coordinates in detail page (no geocoding needed)
  - EventProcessor updates last_seen_at timestamp
  - Stable external_ids for deduplication
  - Weekly recurring events with metadata

  ## Host Handling (Hybrid Approach)
  - Extract from host sections and "Hosted by" patterns
  - Store in description (user-visible)
  - Store in metadata.performer (structured data)
  - NOT stored in performers table (venue-specific hosts, not traveling performers)
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
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id} = job) do
    source_id = args["source_id"]
    event_id = args["event_id"]
    event_data = args["event_data"]

    # Use event_id as external_id for metrics tracking, fallback to job.id
    external_id = "speed_quizzing_event_#{event_id || job_id}"

    Logger.info("🔍 Processing Speed Quizzing event: #{event_id}")

    result =
      with {:ok, html} <- Client.fetch_event_details(event_id),
           {:ok, document} <- parse_html(html),
           venue_data <- VenueExtractor.extract(document, event_id),
           venue_data <- merge_event_data(venue_data, event_data),
           {:ok, transformed} <- transform_and_validate(venue_data, source_id),
           {:ok, events} <- process_event(transformed, source_id) do
        Logger.info("✅ Successfully processed event: #{event_id}")

        # Log host from metadata (hybrid approach - not stored in performers table)
        host_name = get_in(transformed, [:metadata, :performer, :name])

        if host_name do
          Logger.info("🎭 Host: #{host_name} (stored in description + metadata)")
        end

        log_results(events)
        {:ok, %{events: length(events)}}
      else
        {:error, reason} = error ->
          Logger.error("❌ Failed to process event #{event_id}: #{inspect(reason)}")
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
    # Convert GPS coordinates to string format (they may be floats or strings)
    lat_val =
      cond do
        is_binary(event_data["lat"]) or is_float(event_data["lat"]) ->
          event_data["lat"]

        is_binary(event_data["latitude"]) or is_float(event_data["latitude"]) ->
          event_data["latitude"]

        true ->
          nil
      end

    lng_val =
      cond do
        is_binary(event_data["lng"]) or is_float(event_data["lng"]) ->
          event_data["lng"]

        is_binary(event_data["lon"]) or is_float(event_data["lon"]) ->
          event_data["lon"]

        is_binary(event_data["longitude"]) or is_float(event_data["longitude"]) ->
          event_data["longitude"]

        true ->
          nil
      end

    lat = if lat_val, do: to_string(lat_val), else: nil
    lon = if lng_val, do: to_string(lng_val), else: nil

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

  defp log_results(events) do
    count = length(events)

    Logger.info("""
    📊 Processing results:
    - Events processed: #{count}
    """)
  end
end
