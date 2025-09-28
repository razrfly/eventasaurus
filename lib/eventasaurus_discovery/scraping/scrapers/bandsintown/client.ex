defmodule EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client do
  @moduledoc """
  HTTP client for Bandsintown scraping with browser automation support.

  Handles:
  - Browser automation for JavaScript-heavy pages
  - Rate limiting
  - User agent rotation
  - Cookie/session management
  """

  require Logger

  @base_url "https://www.bandsintown.com"
  @default_headers [
    {"User-Agent",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
    {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
    {"Accept-Language", "en-US,en;q=0.5"},
    {"Accept-Encoding", "gzip"},
    {"DNT", "1"},
    {"Connection", "keep-alive"},
    {"Upgrade-Insecure-Requests", "1"}
  ]

  @doc """
  Fetches a city page using Playwright for JavaScript rendering.
  Returns the fully rendered HTML after clicking "View all" and scrolling.
  """
  def fetch_city_page(city_slug, opts \\ []) do
    url = "#{@base_url}/c/#{city_slug}"
    use_playwright = Keyword.get(opts, :use_playwright, true)

    Logger.info("🌐 Fetching city page: #{url}")

    if use_playwright do
      fetch_with_playwright(url, opts)
    else
      fetch_with_httpoison(url, opts)
    end
  end

  @doc """
  Fetches an event detail page.
  Can use simple HTTP client as these pages are usually server-rendered.
  """
  def fetch_event_page(event_path, opts \\ []) do
    url =
      if String.starts_with?(event_path, "http") do
        event_path
      else
        "#{@base_url}#{event_path}"
      end

    Logger.info("🎵 Fetching event page: #{url}")
    fetch_with_httpoison(url, opts)
  end

  # Use Playwright for JavaScript-heavy pages
  defp fetch_with_playwright(url, _opts) do
    Logger.info("🎭 Using Playwright to fetch: #{url}")

    # For now, we'll return a placeholder
    # In production, this would use the Playwright MCP server
    {:error, :playwright_not_configured}

    # TODO: Implement actual Playwright integration
    # with {:ok, browser} <- launch_browser(),
    #      {:ok, page} <- new_page(browser),
    #      :ok <- navigate(page, url),
    #      :ok <- wait_for_load(page),
    #      :ok <- click_view_all(page),
    #      :ok <- scroll_to_load_all(page),
    #      {:ok, html} <- get_page_content(page),
    #      :ok <- close_browser(browser) do
    #   {:ok, html}
    # end
  end

  # Simple HTTP client for server-rendered pages
  defp fetch_with_httpoison(url, opts) do
    options = [
      timeout: Keyword.get(opts, :timeout, 30_000),
      recv_timeout: Keyword.get(opts, :recv_timeout, 30_000),
      follow_redirect: true,
      max_redirect: 3
    ]

    case HTTPoison.get(url, @default_headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers}} ->
        Logger.info("✅ Successfully fetched: #{url}")

        # Check if response is gzipped and decompress if needed
        body =
          if is_gzipped?(headers) do
            case :zlib.gunzip(body) do
              decompressed when is_binary(decompressed) ->
                Logger.debug("📦 Decompressed gzipped response")
                decompressed

              _ ->
                Logger.debug("📦 Failed to decompress, using original body")
                body
            end
          else
            body
          end

        # Ensure UTF-8 validity at HTTP entry point
        clean_body = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(body)
        {:ok, clean_body}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("❌ HTTP #{status_code} for: #{url}")
        {:error, {:http_error, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Failed to fetch #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp is_gzipped?(headers) do
    Enum.any?(headers, fn
      {"content-encoding", value} -> String.contains?(String.downcase(value), "gzip")
      {"Content-Encoding", value} -> String.contains?(String.downcase(value), "gzip")
      _ -> false
    end)
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

  ## Parameters
    - latitude: The latitude of the city
    - longitude: The longitude of the city
    - page: The page number to fetch (default: 2)
    - opts: Additional options
  """
  def fetch_next_events_page(latitude, longitude, page \\ 2, opts \\ []) do
    url =
      "#{@base_url}/all-dates/fetch-next/upcomingEvents?page=#{page}&longitude=#{longitude}&latitude=#{latitude}"

    headers = [
      {"User-Agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
      {"Accept", "application/json, text/javascript, */*; q=0.01"},
      {"Accept-Language", "en-US,en;q=0.5"},
      {"Accept-Encoding", "gzip"},
      {"X-Requested-With", "XMLHttpRequest"},
      {"Referer", "#{@base_url}"},
      {"DNT", "1"},
      {"Connection", "keep-alive"}
    ]

    options = [
      timeout: Keyword.get(opts, :timeout, 10_000),
      recv_timeout: Keyword.get(opts, :recv_timeout, 10_000),
      follow_redirect: true,
      max_redirect: 3
    ]

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: response_headers}} ->
        # Check if response is gzipped and decompress if needed
        body =
          if is_gzipped?(response_headers) do
            case :zlib.gunzip(body) do
              decompressed when is_binary(decompressed) ->
                Logger.debug("📦 Decompressed gzipped response")
                decompressed

              _ ->
                Logger.debug("📦 Failed to decompress, using original body")
                body
            end
          else
            body
          end

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

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("❌ HTTP #{status_code} for page #{page}")
        {:error, {:http_error, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
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
        case EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Extractor.extract_events_from_html_fragment(
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
      "image_url" => Map.get(event, "artistImageSrc", "") || Map.get(event, "fallbackImageUrl", ""),
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
