defmodule EventasaurusDiscovery.Sources.Kupbilecik.Client do
  @moduledoc """
  HTTP client for fetching content from kupbilecik.pl.

  Handles two types of requests:
  1. **Sitemap requests**: Plain HTTP (XML, no JS needed)
  2. **Event page requests**: Via Http.Client with Zyte adapter (JS required)

  ## Access Pattern

  Kupbilecik.pl is a React/Webpack SPA that requires JavaScript execution.
  Event pages return only JS bundles without content when fetched directly.

  - Sitemaps: HTTPoison direct (XML is static)
  - Event pages: Http.Client with source: :kupbilecik -> Zyte browserHtml mode

  ## Rate Limiting

  - 3 second delay between requests (configurable in Config)
  - Zyte API handles browser rendering and rate limiting internally
  """

  require Logger

  alias EventasaurusDiscovery.Sources.Kupbilecik.Config
  alias EventasaurusDiscovery.Http.Client, as: HttpClient

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

    Logger.info("📊 Total event URLs found: #{length(event_entries)}")
    {:ok, event_entries}
  end

  @doc """
  Fetches an event page using Http.Client with Zyte adapter.

  Uses browser rendering to execute JavaScript and get full content.

  ## Options

  - `:retries` - Maximum retry attempts (default: 3)

  ## Examples

      iex> fetch_page("https://www.kupbilecik.pl/imprezy/186000/")
      {:ok, "<html>...</html>"}
  """
  def fetch_page(url, opts \\ []) do
    Logger.debug("🌐 Fetching kupbilecik page via Zyte: #{url}")

    # Apply rate limiting
    apply_rate_limit()

    # Use Http.Client with kupbilecik source config (should use Zyte)
    case HttpClient.fetch(url, source: :kupbilecik, mode: :browser_html) do
      {:ok, body, metadata} ->
        Logger.debug(
          "✅ Fetched page (#{byte_size(body)} bytes) via #{metadata.adapter} in #{metadata.duration_ms}ms"
        )

        {:ok, body}

      {:error, {:all_adapters_failed, blocked_by}} ->
        Logger.warning("🚫 All adapters failed for #{url}: #{inspect(blocked_by)}")
        handle_retry(url, opts, :all_adapters_failed)

      {:error, {:timeout, type}} ->
        Logger.warning("⏱️ Timeout (#{type}) fetching #{url}")
        handle_retry(url, opts, {:timeout, type})

      {:error, {:zyte_error, status, message}} ->
        Logger.warning("⚠️ Zyte error (#{status}): #{message} for #{url}")
        handle_retry(url, opts, {:zyte_error, status})

      {:error, reason} ->
        Logger.error("❌ Failed to fetch #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches event page and returns raw HTML for extraction.

  Convenience wrapper around fetch_page/2 for EventDetailJob.
  """
  def fetch_event_page(url) do
    fetch_page(url)
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
end
