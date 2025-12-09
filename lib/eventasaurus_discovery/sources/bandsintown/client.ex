defmodule EventasaurusDiscovery.Sources.Bandsintown.Client do
  @moduledoc """
  HTTP client for Bandsintown scraping using the unified HTTP abstraction layer.

  Uses `EventasaurusDiscovery.Http.Client` with automatic Zyte proxy routing
  to bypass Cloudflare blocking.

  Handles:
  - Automatic proxy routing via Http.Client (configured as :zyte strategy)
  - Rate limiting
  - Blocking detection and fallback
  - UTF-8 sanitization
  """

  require Logger

  alias EventasaurusDiscovery.Http.Client, as: HttpClient

  @base_url "https://www.bandsintown.com"

  @doc """
  Fetches a city page using the unified HTTP client.

  Uses Zyte proxy by default (configured in runtime.exs) which provides
  browser rendering to handle JavaScript-heavy pages.

  ## Options
    - :timeout - Request timeout in milliseconds (default: 30_000)
    - :mode - Zyte mode, :browser_html (default) or :http_response_body
  """
  @spec fetch_city_page(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def fetch_city_page(city_slug, opts \\ []) do
    url = "#{@base_url}/c/#{city_slug}"

    Logger.info("🌐 Fetching city page: #{url}")

    timeout = Keyword.get(opts, :timeout, 30_000)
    mode = Keyword.get(opts, :mode, :browser_html)

    case HttpClient.fetch(url, source: :bandsintown, timeout: timeout, mode: mode) do
      {:ok, body, metadata} ->
        Logger.info("✅ Successfully fetched city page via #{metadata.adapter}: #{url}")
        clean_body = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(body)
        {:ok, clean_body}

      {:error, {:http_error, status_code, _body, _metadata}} ->
        Logger.error("❌ HTTP #{status_code} for: #{url}")
        {:error, {:http_error, status_code}}

      {:error, {:all_adapters_failed, blocked_by}} ->
        Logger.error("❌ All HTTP adapters failed for: #{url}")
        Logger.error("   Blocked by: #{inspect(Enum.map(blocked_by, & &1.adapter))}")
        {:error, :all_adapters_blocked}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches an event detail page using the unified HTTP client.

  Event detail pages are also protected by Cloudflare, so we use Zyte
  via the pre-configured :bandsintown strategy.

  ## Options
    - :timeout - Request timeout in milliseconds (default: 30_000)
    - :mode - Zyte mode, :browser_html (default) or :http_response_body
  """
  def fetch_event_page(event_path, opts \\ []) do
    url =
      if String.starts_with?(event_path, "http") do
        event_path
      else
        "#{@base_url}#{event_path}"
      end

    Logger.info("🎵 Fetching event page: #{url}")

    timeout = Keyword.get(opts, :timeout, 30_000)
    mode = Keyword.get(opts, :mode, :browser_html)

    case HttpClient.fetch(url, source: :bandsintown, timeout: timeout, mode: mode) do
      {:ok, body, metadata} ->
        Logger.info("✅ Successfully fetched event page via #{metadata.adapter}: #{url}")
        clean_body = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(body)
        {:ok, clean_body}

      {:error, {:http_error, status_code, _body, _metadata}} ->
        Logger.error("❌ HTTP #{status_code} for: #{url}")
        {:error, {:http_error, status_code}}

      {:error, {:all_adapters_failed, blocked_by}} ->
        Logger.error("❌ All HTTP adapters failed for event page: #{url}")
        Logger.error("   Blocked by: #{inspect(Enum.map(blocked_by, & &1.adapter))}")
        {:error, :all_adapters_blocked}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Checks if we should use Playwright based on the page content.
  Some cities might work without JavaScript.
  """
  def requires_javascript?(html) do
    # Check for signs that JavaScript is required
    cond do
      String.contains?(html, "View all") -> true
      String.contains?(html, "Load more") -> true
      # Next.js app
      String.contains?(html, "__NEXT_DATA__") -> true
      String.contains?(html, "React") -> true
      true -> false
    end
  end

  @doc """
  Fetches additional events from the pagination API endpoint.
  This is used to get events beyond the initial 36 shown on the city page.

  Uses Http.Client with :http_response_body mode for JSON API responses.

  ## Parameters
    - latitude: The latitude of the city
    - longitude: The longitude of the city
    - page: The page number to fetch (default: 2)
    - opts: Additional options
  """
  def fetch_next_events_page(latitude, longitude, page \\ 2, opts \\ []) do
    url =
      "#{@base_url}/all-dates/fetch-next/upcomingEvents?page=#{page}&longitude=#{longitude}&latitude=#{latitude}"

    timeout = Keyword.get(opts, :timeout, 10_000)

    # Use http_response_body mode for JSON API endpoints (faster than browser rendering)
    case HttpClient.fetch(url, source: :bandsintown, timeout: timeout, mode: :http_response_body) do
      {:ok, body, _metadata} ->
        # Ensure UTF-8 validity at HTTP entry point
        clean_body = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(body)

        # Try to parse as JSON first
        case Jason.decode(clean_body) do
          {:ok, json_data} ->
            # Clean JSON data recursively if it contains strings
            clean_json = EventasaurusDiscovery.Utils.UTF8.validate_map_strings(json_data)
            {:ok, clean_json}

          {:error, _} ->
            # If not JSON, might be HTML (already cleaned)
            {:ok, clean_body}
        end

      {:error, {:http_error, status_code, _body, _metadata}} ->
        Logger.error("❌ HTTP #{status_code} for page #{page}")
        {:error, {:http_error, status_code}}

      {:error, {:all_adapters_failed, blocked_by}} ->
        Logger.error("❌ All HTTP adapters failed for pagination page #{page}")
        Logger.error("   Blocked by: #{inspect(Enum.map(blocked_by, & &1.adapter))}")
        {:error, :all_adapters_blocked}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch page #{page}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches all events from a city by paginating through the API.
  Returns a list of all events found.

  ## Parameters
    - latitude: The latitude of the city
    - longitude: The longitude of the city
    - city_slug: The city slug for fetching the initial page
    - opts: Additional options including :max_pages
  """
  def fetch_all_city_events(latitude, longitude, _city_slug, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, 10)

    # Start directly with the API pagination - page 1
    all_events = fetch_additional_pages(latitude, longitude, [], 1, max_pages, opts)

    {:ok, all_events}
  end

  defp fetch_additional_pages(latitude, longitude, acc_events, current_page, max_pages, opts)
       when current_page <= max_pages do
    # Rate limit between requests
    rate_limit(2000)

    case fetch_next_events_page(latitude, longitude, current_page, opts) do
      {:ok, json_data} when is_map(json_data) ->
        # Extract events from JSON response
        new_events = extract_events_from_json_response(json_data)

        if length(new_events) > 0 do
          fetch_additional_pages(
            latitude,
            longitude,
            acc_events ++ new_events,
            current_page + 1,
            max_pages,
            opts
          )
        else
          acc_events
        end

      {:ok, _html} ->
        Logger.warning("⚠️ Got HTML response instead of JSON for page #{current_page}")
        acc_events

      {:error, {:http_error, 404}} ->
        acc_events

      {:error, reason} ->
        Logger.error("❌ Error fetching page #{current_page}: #{inspect(reason)}")
        acc_events
    end
  end

  defp fetch_additional_pages(_latitude, _longitude, acc_events, _current_page, _max_pages, _opts) do
    acc_events
  end

  defp extract_events_from_json_response(json_data) do
    # The response might have events in different structures
    # Need to inspect actual response structure
    case json_data do
      %{"events" => events} when is_list(events) ->
        Enum.map(events, &transform_api_event/1)

      %{"data" => %{"events" => events}} when is_list(events) ->
        Enum.map(events, &transform_api_event/1)

      %{"html" => html} when is_binary(html) ->
        # If it returns HTML, we need to parse it
        case EventasaurusDiscovery.Sources.Bandsintown.Extractor.extract_events_from_html_fragment(
               html
             ) do
          {:ok, events} -> events
          _ -> []
        end

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

    # IMPORTANT: Use string keys (not atoms) for compatibility with Transformer module
    %{
      "url" => Map.get(event, "eventUrl", ""),
      "artist_name" => Map.get(event, "artistName", ""),
      "venue_name" => Map.get(event, "venueName", ""),
      "date" => Map.get(event, "startsAt", ""),
      "description" => Map.get(event, "title", ""),
      "image_url" =>
        Map.get(event, "artistImageSrc", "") || Map.get(event, "fallbackImageUrl", ""),
      "external_id" => external_id
    }
  end

  @doc """
  Rate limit helper - ensures we don't make requests too quickly.
  """
  def rate_limit(delay_ms \\ 3000) do
    Process.sleep(delay_ms)
  end
end
