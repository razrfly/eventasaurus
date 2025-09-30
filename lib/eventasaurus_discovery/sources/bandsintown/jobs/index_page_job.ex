defmodule EventasaurusDiscovery.Sources.Bandsintown.Jobs.IndexPageJob do
  @moduledoc """
  Oban job for processing individual Bandsintown API pages.

  This job is part of a distributed scraping strategy that prevents timeouts
  by breaking up the API fetching into smaller, concurrent units of work.

  Each IndexPageJob:
  1. Fetches a single page from the Bandsintown API
  2. Extracts events from that API response
  3. Schedules EventDetailJobs for each event found

  This allows for:
  - Better failure isolation (one page failing doesn't affect others)
  - Concurrent processing of multiple API pages
  - More granular progress tracking
  - Ability to resume from partial failures
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Validate and normalize input arguments
    with {:ok, page_number} <- validate_integer(args["page_number"], "page_number"),
         {:ok, latitude} <- validate_float(args["latitude"], "latitude"),
         {:ok, longitude} <- validate_float(args["longitude"], "longitude"),
         {:ok, source_id} <- validate_integer(args["source_id"], "source_id"),
         {:ok, city_id} <- validate_integer(args["city_id"], "city_id"),
         true <- page_number >= 1 || {:error, "page_number", "must be >= 1"},
         true <- source_id > 0 || {:error, "source_id", "must be > 0"},
         true <- city_id > 0 || {:error, "city_id", "must be > 0"} do

      # Optional arguments with defaults
      limit = validate_optional_integer(args["limit"])
      total_pages = validate_optional_integer(args["total_pages"])
      city_name = args["city_name"] || "Unknown"

      Logger.info("""
      🎵 Processing Bandsintown API page
      City: #{city_name}
      Page: #{page_number}/#{total_pages || "unknown"}
      Source ID: #{source_id}
      City ID: #{city_id}
      """)

      process_page(page_number, latitude, longitude, source_id, city_id, limit, total_pages)
    else
      {:error, field, reason} ->
        Logger.error("❌ Invalid job arguments - #{field}: #{reason}")
        {:discard, "invalid_args_#{field}"}
    end
  end

  defp process_page(page_number, latitude, longitude, source_id, city_id, limit, _total_pages) do
    # Fetch the API page
    case Client.fetch_next_events_page(latitude, longitude, page_number) do
      {:ok, json_data} when is_map(json_data) ->
        process_api_response(json_data, page_number, source_id, city_id, limit)

      {:ok, _html} ->
        Logger.warning("⚠️ Got HTML response instead of JSON for page #{page_number}")
        {:ok, :no_json_data}

      {:error, {:http_error, 404}} ->
        Logger.info("📭 Page #{page_number} not found - likely past last page")
        {:ok, :no_more_pages}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch page #{page_number}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Validation helpers
  defp validate_integer(nil, field), do: {:error, field, "is required"}
  defp validate_integer(value, _field) when is_integer(value), do: {:ok, value}
  defp validate_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, field, "invalid integer: #{inspect(value)}"}
    end
  end
  defp validate_integer(value, field), do: {:error, field, "expected integer, got: #{inspect(value)}"}

  defp validate_float(nil, field), do: {:error, field, "is required"}
  defp validate_float(value, _field) when is_float(value), do: {:ok, value}
  defp validate_float(value, _field) when is_integer(value), do: {:ok, value * 1.0}
  defp validate_float(value, field) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, field, "invalid float: #{inspect(value)}"}
    end
  end
  defp validate_float(value, field), do: {:error, field, "expected float, got: #{inspect(value)}"}

  defp validate_optional_integer(nil), do: nil
  defp validate_optional_integer(value) when is_integer(value) and value > 0, do: value
  defp validate_optional_integer(value) when is_integer(value), do: nil  # Reject non-positive
  defp validate_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end
  defp validate_optional_integer(_), do: nil

  defp process_api_response(json_data, page_number, source_id, city_id, _limit) do
    # Extract events from JSON response
    events = extract_events_from_json(json_data)

    if length(events) > 0 do
      Logger.info("📋 Extracted #{length(events)} events from page #{page_number}")

      # Apply limit calculation
      # For async mode, limit is already enforced by only scheduling necessary pages
      # We process all events on scheduled pages
      events_to_process = events

      # Schedule detail jobs for each event
      scheduled_count = schedule_detail_jobs(events_to_process, source_id, city_id, page_number)

      Logger.info("""
      ✅ API page #{page_number} processed
      Events found: #{length(events)}
      Detail jobs scheduled: #{scheduled_count}
      """)

      {:ok, %{
        page: page_number,
        events_found: length(events),
        jobs_scheduled: scheduled_count
      }}
    else
      Logger.info("📭 No events on page #{page_number}")
      {:ok, :no_events}
    end
  end

  defp extract_events_from_json(json_data) do
    # The response might have events in different structures
    case json_data do
      %{"events" => events} when is_list(events) ->
        Enum.map(events, &transform_api_event/1)

      %{"data" => %{"events" => events}} when is_list(events) ->
        Enum.map(events, &transform_api_event/1)

      %{"html" => html} when is_binary(html) ->
        # If it returns HTML fragment, we could parse it
        # But for now, return empty as this shouldn't happen with API calls
        Logger.warning("⚠️ Unexpected HTML in JSON response")
        []

      _ ->
        Logger.warning("⚠️ Unknown JSON response structure: #{inspect(Map.keys(json_data))}")
        []
    end
  end

  defp transform_api_event(event) do
    # Extract event ID from URL if not directly available
    external_id =
      case Map.get(event, "eventUrl", "") do
        url when is_binary(url) ->
          case Regex.run(~r/\/e\/(\d+)/, url) do
            [_, id] -> id
            _ -> ""
          end

        _ ->
          ""
      end

    # Extract and validate image URL
    image_url =
      case Map.get(event, "artistImageSrc") do
        nil -> Map.get(event, "fallbackImageUrl")
        "" -> Map.get(event, "fallbackImageUrl")
        url -> url
      end

    # IMPORTANT: Use string keys (not atoms) for compatibility with Transformer module
    # Also extract venue location data if available
    %{
      "url" => Map.get(event, "eventUrl", ""),
      "artist_name" => Map.get(event, "artistName", ""),
      "venue_name" => Map.get(event, "venueName", ""),
      "venue_city" => Map.get(event, "venueCity"),
      "venue_country" => Map.get(event, "venueCountry"),
      "venue_latitude" => Map.get(event, "venueLat"),
      "venue_longitude" => Map.get(event, "venueLng"),
      "date" => Map.get(event, "startsAt", ""),
      "description" => Map.get(event, "title", ""),
      "image_url" => image_url,
      "external_id" => external_id
    }
  end

  defp schedule_detail_jobs(events, source_id, city_id, page_number) do
    alias EventasaurusDiscovery.Services.EventFreshnessChecker

    # Add bandsintown_ prefix to external_id for freshness checking
    # This matches the format stored in public_event_sources table
    events_with_prefixed_ids = Enum.map(events, fn event ->
      Map.update!(event, "external_id", fn id -> "bandsintown_#{id}" end)
    end)

    # Filter to events needing processing based on freshness
    events_to_process = EventFreshnessChecker.filter_events_needing_processing(
      events_with_prefixed_ids,
      source_id
    )

    skipped = length(events) - length(events_to_process)
    threshold = EventFreshnessChecker.get_threshold()

    Logger.info("📋 Bandsintown page #{page_number}: Processing #{length(events_to_process)}/#{length(events)} events (#{skipped} skipped, threshold: #{threshold}h)")

    # Calculate base delay for this page to distribute load
    # Add staggered delays to respect rate limits (3 seconds between requests)
    base_delay = (page_number - 1) * length(events_to_process) * 3

    scheduled_jobs =
      events_to_process
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        # Stagger job execution with rate limiting
        delay_seconds = base_delay + (index * 3)
        scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

        # Clean UTF-8 before storing in database
        job_args = %{
          "event_data" => event,
          "source_id" => source_id,
          "city_id" => city_id,
          # external_id already has bandsintown_ prefix from freshness check above
          "external_id" => event["external_id"],
          "from_page" => page_number
        }
        |> EventasaurusDiscovery.Utils.UTF8.validate_map_strings()

        # Schedule the detail job
        EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob.new(
          job_args,
          queue: :scraper_detail,
          scheduled_at: scheduled_at
        )
        |> Oban.insert()
      end)

    # Count successful insertions
    Enum.count(scheduled_jobs, fn
      {:ok, _} -> true
      _ -> false
    end)
  end
end