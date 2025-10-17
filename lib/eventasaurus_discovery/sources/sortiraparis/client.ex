defmodule EventasaurusDiscovery.Sources.Sortiraparis.Client do
  @moduledoc """
  HTTP client for fetching content from Sortiraparis.com website.

  Handles:
  - Rate limiting (4-5s between requests)
  - Retries with exponential backoff
  - Bot protection (401 errors ~30% of pages)
  - Browser-like headers to reduce bot detection
  - UTF-8 encoding for French content
  - Playwright fallback (TODO: Phase 3+)

  ## Bot Protection Strategy

  Based on POC findings:
  - ~70% success rate with browser-like headers
  - ~30% return 401 (Unauthorized) even with proper headers
  - Mitigation: Conservative rate limiting + Playwright fallback

  See POC results: `docs/sortiraparis_poc_results.md`
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Sortiraparis.Config

  @doc """
  Fetch HTML content from a given URL with rate limiting and retries.

  ## Options

  - `:retries` - Maximum retry attempts (default: 3)
  - `:attempt` - Current attempt number (default: 1)
  - `:skip_rate_limit` - Skip rate limiting for redirects (default: false)
  - `:use_playwright` - Use Playwright for stubborn 401 errors (default: false, TODO: Phase 3+)

  ## Examples

      iex> fetch_page("https://www.sortiraparis.com/articles/319282-indochine-concert")
      {:ok, "<html>...</html>"}

      iex> fetch_page("https://www.sortiraparis.com/nonexistent")
      {:error, :not_found}
  """
  def fetch_page(url, opts \\ []) do
    retries = Keyword.get(opts, :retries, 3)
    attempt = Keyword.get(opts, :attempt, 1)

    # Apply rate limiting (except on first request or redirects)
    if attempt == 1 && !Keyword.get(opts, :skip_rate_limit, false) do
      apply_rate_limit()
    end

    Logger.debug("🌐 Fetching Sortiraparis page: #{url} (attempt #{attempt}/#{retries})")

    case HTTPoison.get(url, Config.headers(),
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers}} ->
        decoded_body = decode_response_body(body, headers)
        encoded_body = ensure_utf8(decoded_body)
        {:ok, encoded_body}

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        # Bot protection triggered
        Logger.warning("🚫 Bot protection 401 on: #{url}")

        # TODO Phase 3+: Implement Playwright fallback
        # if Keyword.get(opts, :use_playwright, false) do
        #   fetch_with_playwright(url)
        # else
        #   {:error, :bot_protection}
        # end

        {:error, :bot_protection}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.warning("❌ Page not found: #{url}")
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: status_code} = response}
      when status_code in 301..302 ->
        # Handle redirects
        case get_redirect_location(response) do
          {:ok, redirect_url} ->
            Logger.info("↪️  Following redirect: #{redirect_url}")
            fetch_page(redirect_url, Keyword.put(opts, :skip_rate_limit, true))

          :error ->
            {:error, :redirect_failed}
        end

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        # Rate limited - wait longer and retry
        Logger.warning("⏳ Rate limited, waiting 30 seconds...")
        Process.sleep(30_000)
        retry_request(url, opts, retries, attempt)

      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code >= 500 ->
        # Server error - retry with backoff
        Logger.warning("⚠️  Server error (#{status_code}), retrying...")
        retry_request(url, opts, retries, attempt)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("❌ Unexpected status code: #{status_code}")
        {:error, {:unexpected_status, status_code}}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️  Request timeout, retrying...")
        retry_request(url, opts, retries, attempt)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ HTTP error: #{inspect(reason)}")
        retry_request(url, opts, retries, attempt)
    end
  end

  @doc """
  Fetch sitemap XML from given URL.

  Returns parsed sitemap with list of URLs.

  ## Examples

      iex> fetch_sitemap("https://www.sortiraparis.com/sitemap-en-1.xml")
      {:ok, ["https://...", "https://...", ...]}
  """
  def fetch_sitemap(url, opts \\ []) do
    case fetch_page(url, opts) do
      {:ok, xml_body} ->
        parse_sitemap(xml_body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch sitemap index and extract all sitemap URLs.

  ## Examples

      iex> fetch_sitemap_index("https://www.sortiraparis.com/sitemap-index.xml")
      {:ok, ["https://.../sitemap-en-1.xml", ...]}
  """
  def fetch_sitemap_index(url, opts \\ []) do
    case fetch_page(url, opts) do
      {:ok, xml_body} ->
        parse_sitemap_index(xml_body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp retry_request(url, opts, retries, attempt) when attempt < retries do
    # Exponential backoff: 2^attempt seconds
    wait_time = :math.pow(2, attempt) |> round() |> Kernel.*(1000)
    Logger.info("⏳ Waiting #{wait_time}ms before retry...")
    Process.sleep(wait_time)

    fetch_page(url, Keyword.merge(opts, retries: retries, attempt: attempt + 1))
  end

  defp retry_request(_url, _opts, _retries, _attempt) do
    {:error, :max_retries_exceeded}
  end

  defp apply_rate_limit do
    # Apply rate limiting (milliseconds)
    # Conservative 5 second wait to avoid bot protection
    wait_time = Config.rate_limit() * 1000
    Process.sleep(wait_time)
  end

  defp decode_response_body(body, headers) do
    # Check if response is compressed
    try do
      case get_header(headers, "content-encoding") do
        "gzip" ->
          :zlib.gunzip(body)
        "deflate" ->
          :zlib.uncompress(body)
        "br" ->
          # Check if Brotli is available before attempting decode
          if Code.ensure_loaded?(:brotli) and function_exported?(:brotli, :decode, 1) do
            :brotli.decode(body)
          else
            body
          end
        _ ->
          body
      end
    rescue
      _ -> body
    end
  end

  defp ensure_utf8(body) when is_binary(body) do
    # Ensure valid UTF-8 for French content
    EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8_with_logging(
      body,
      "Sortiraparis HTTP response"
    )
  end

  defp ensure_utf8(body), do: body

  defp get_redirect_location(response) do
    case get_header(response.headers, "Location") do
      nil -> :error
      location -> {:ok, location}
    end
  end

  defp get_header(headers, key) do
    headers
    |> Enum.find(fn {k, _} -> String.downcase(k) == String.downcase(key) end)
    |> case do
      {_, value} -> value
      _ -> nil
    end
  end

  defp parse_sitemap(xml_body) do
    # Simple XML parsing for <loc> tags
    # Returns list of URLs from sitemap
    case Regex.scan(~r{<loc>(.*?)</loc>}, xml_body, capture: :all_but_first) do
      [] ->
        {:error, :no_urls_found}

      matches ->
        urls = Enum.map(matches, fn [url] -> url end)
        {:ok, urls}
    end
  end

  defp parse_sitemap_index(xml_body) do
    # Parse sitemap index to extract sitemap URLs
    case Regex.scan(~r{<loc>(.*?)</loc>}, xml_body, capture: :all_but_first) do
      [] ->
        {:error, :no_sitemaps_found}

      matches ->
        sitemap_urls = Enum.map(matches, fn [url] -> url end)
        {:ok, sitemap_urls}
    end
  end
end
