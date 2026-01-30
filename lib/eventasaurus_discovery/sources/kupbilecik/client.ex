defmodule EventasaurusDiscovery.Sources.Kupbilecik.Client do
  @moduledoc """
  HTTP client for fetching content from kupbilecik.pl.

  Handles two types of requests:
  1. **Sitemap requests**: Plain HTTP (XML, no JS needed)
  2. **Event page requests**: Plain HTTP (SSR site, no JS needed)

  ## Access Pattern

  Kupbilecik.pl uses **Server-Side Rendering (SSR)** for SEO purposes.
  All event data is present in the initial HTML response, including:
  - Meta tags (og:title, og:description, og:image)
  - Semantic HTML structure with event details
  - Schema.org markup

  **No JavaScript rendering (Zyte) is required** - plain HTTP fetches
  return all necessary data for extraction.

  ## Rate Limiting

  - 1 second delay between requests (configurable in Config)
  - Respects robots.txt crawl delay recommendations
  """

  require Logger

  alias EventasaurusDiscovery.Sources.Kupbilecik.Config

  @user_agent "Mozilla/5.0 (compatible; Eventasaurus/1.0; +https://eventasaurus.com)"

  @doc """
  Fetches a sitemap XML file and extracts event URLs.

  Sitemaps are plain XML files that don't require JS rendering.

  ## Examples

      iex> fetch_sitemap("https://www.kupbilecik.pl/sitemap_imprezy-1.xml")
      {:ok, ["https://www.kupbilecik.pl/imprezy/186000/", ...]}
  """
  def fetch_sitemap(url) do
    Logger.debug("📄 Fetching kupbilecik sitemap: #{url}")

    case HTTPoison.get(url, Config.sitemap_headers(),
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_sitemap_urls(body)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.warning("⚠️ Sitemap fetch failed with status #{status_code}: #{url}")
        {:error, {:http_error, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Sitemap fetch error: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  @doc """
  Fetches all event URLs from all configured sitemaps.

  Returns a deduplicated list of event URLs with metadata.

  ## Examples

      iex> fetch_all_sitemap_urls()
      {:ok, [%{url: "https://...", event_id: "186000"}, ...]}
  """
  def fetch_all_sitemap_urls do
    Logger.info("🗺️ Fetching all kupbilecik sitemaps")

    results =
      Config.sitemap_urls()
      |> Enum.map(fn sitemap_url ->
        case fetch_sitemap(sitemap_url) do
          {:ok, urls} ->
            Logger.debug("✅ Found #{length(urls)} URLs in #{sitemap_url}")
            urls

          {:error, reason} ->
            Logger.warning("⚠️ Failed to fetch #{sitemap_url}: #{inspect(reason)}")
            []
        end
      end)
      |> List.flatten()
      |> Enum.uniq()

    # Filter to only event URLs and add metadata
    event_entries =
      results
      |> Enum.filter(&Config.is_event_url?/1)
      |> Enum.map(fn url ->
        %{
          url: url,
          event_id: Config.extract_event_id(url)
        }
      end)
      |> Enum.reject(fn entry -> is_nil(entry.event_id) end)
      # Sort by event_id descending (higher IDs = newer events)
      |> Enum.sort_by(
        fn entry ->
          case Integer.parse(entry.event_id) do
            {num, _} -> num
            _ -> 0
          end
        end,
        :desc
      )

    Logger.info("📊 Total event URLs found: #{length(event_entries)}")
    {:ok, event_entries}
  end

  @doc """
  Fetches an event page using plain HTTP.

  Kupbilecik.pl uses Server-Side Rendering (SSR), so all event data
  is present in the initial HTML response. No JavaScript rendering needed.

  ## Options

  - `:retries` - Maximum retry attempts (default: 3)

  ## Examples

      iex> fetch_page("https://www.kupbilecik.pl/imprezy/186000/")
      {:ok, "<html>...</html>"}
  """
  def fetch_page(url, opts \\ []) do
    Logger.debug("🌐 Fetching kupbilecik page via plain HTTP: #{url}")

    # Apply rate limiting
    apply_rate_limit()

    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "pl,en;q=0.5"},
      # Note: Do NOT include Accept-Encoding: gzip as HTTPoison doesn't auto-decompress
      # and we want raw HTML content
      {"Connection", "keep-alive"}
    ]

    case HTTPoison.get(url, headers,
           follow_redirect: true,
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Logger.debug("✅ Fetched page (#{byte_size(body)} bytes) via plain HTTP")
        {:ok, ensure_utf8(body)}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.warning("⚠️ Event not found (404): #{url}")
        {:error, {:http_error, 404}}

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.warning("⚠️ HTTP #{status_code} for #{url}")
        handle_retry(url, opts, {:http_error, status_code})

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Timeout fetching #{url}")
        handle_retry(url, opts, :timeout)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Failed to fetch #{url}: #{inspect(reason)}")
        handle_retry(url, opts, {:network_error, reason})
    end
  end

  @doc """
  Fetches event page and returns raw HTML for extraction.

  Convenience wrapper around fetch_page/2 for EventDetailJob.
  Converts 404 errors to :not_found for consistent error handling.
  """
  def fetch_event_page(url) do
    case fetch_page(url) do
      {:ok, body} -> {:ok, body}
      {:error, {:http_error, 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp parse_sitemap_urls(xml_body) do
    # Extract all <loc> URLs from sitemap XML
    case Regex.scan(~r{<loc>(.*?)</loc>}, xml_body, capture: :all_but_first) do
      [] ->
        Logger.warning("⚠️ No URLs found in sitemap")
        {:ok, []}

      matches ->
        urls =
          matches
          |> Enum.map(fn [url] -> url end)
          |> Enum.map(&String.trim/1)
          |> Enum.map(&decode_xml_entities/1)

        {:ok, urls}
    end
  end

  defp decode_xml_entities(url) do
    url
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  defp apply_rate_limit do
    wait_time = Config.rate_limit() * 1000
    Process.sleep(wait_time)
  end

  defp handle_retry(url, opts, _reason) do
    retries = Keyword.get(opts, :retries, 3)
    attempt = Keyword.get(opts, :attempt, 1)

    if attempt < retries do
      # Exponential backoff
      wait_time = :math.pow(2, attempt) |> round() |> Kernel.*(1000)
      Logger.info("⏳ Retry #{attempt + 1}/#{retries} in #{wait_time}ms...")
      Process.sleep(wait_time)

      fetch_page(url, Keyword.merge(opts, attempt: attempt + 1, retries: retries))
    else
      Logger.error("❌ Max retries exceeded for #{url}")
      {:error, :max_retries_exceeded}
    end
  end

  defp ensure_utf8(body) when is_binary(body) do
    EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8_with_logging(body, "Kupbilecik HTTP response")
  end

  defp ensure_utf8(body), do: body
end
