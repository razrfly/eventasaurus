defmodule EventasaurusDiscovery.Sources.Karnet.Client do
  @moduledoc """
  HTTP client for fetching content from Karnet Kraków website.

  Handles:
  - Rate limiting
  - Retries with exponential backoff
  - Polish character encoding (UTF-8)
  - Error handling
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Karnet.Config

  @doc """
  Fetch HTML content from a given URL with rate limiting and retries.
  """
  def fetch_page(url, opts \\ []) do
    retries = Keyword.get(opts, :retries, 3)
    attempt = Keyword.get(opts, :attempt, 1)

    # Apply rate limiting (except on first request)
    if attempt == 1 && !Keyword.get(opts, :skip_rate_limit, false) do
      apply_rate_limit()
    end

    Logger.debug("🌐 Fetching Karnet page: #{url} (attempt #{attempt}/#{retries})")

    case HTTPoison.get(url, Config.headers(),
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: headers}} ->
        # Check if response is compressed
        decoded_body =
          case get_header(headers, "content-encoding") do
            "gzip" -> :zlib.gunzip(body)
            "deflate" -> :zlib.uncompress(body)
            _ -> body
          end

        # Ensure proper UTF-8 encoding for Polish content
        encoded_body = ensure_utf8(decoded_body)
        {:ok, encoded_body}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.warning("❌ Page not found: #{url}")
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: status_code} = response}
      when status_code in 301..302 ->
        # Handle redirects
        case get_redirect_location(response) do
          {:ok, redirect_url} ->
            Logger.info("↪️ Following redirect: #{redirect_url}")
            fetch_page(redirect_url, Keyword.put(opts, :skip_rate_limit, true))

          :error ->
            {:error, :redirect_failed}
        end

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        # Rate limited - wait longer and retry
        Logger.warning("⏳ Rate limited, waiting longer...")
        # Wait 30 seconds
        Process.sleep(30_000)
        retry_request(url, opts, retries, attempt)

      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code >= 500 ->
        # Server error - retry with backoff
        Logger.warning("⚠️ Server error (#{status_code}), retrying...")
        retry_request(url, opts, retries, attempt)

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("❌ Unexpected status code: #{status_code}")
        {:error, {:unexpected_status, status_code}}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Request timeout, retrying...")
        retry_request(url, opts, retries, attempt)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ HTTP error: #{inspect(reason)}")
        retry_request(url, opts, retries, attempt)
    end
  end

  @doc """
  Fetch all pages of events index with pagination.

  Returns a list of HTML bodies for all pages.
  """
  def fetch_all_index_pages(max_pages \\ nil) do
    fetch_pages_recursive(1, max_pages, [])
  end

  defp fetch_pages_recursive(page_num, max_pages, acc)
       when is_integer(max_pages) and page_num > max_pages do
    {:ok, Enum.reverse(acc)}
  end

  defp fetch_pages_recursive(page_num, max_pages, acc) do
    url = Config.build_events_url(page_num)

    case fetch_page(url) do
      {:ok, html} ->
        Logger.info("✅ Fetched page #{page_num}")

        # Check if this page has events (to detect when we've gone past the last page)
        if has_events?(html) do
          fetch_pages_recursive(page_num + 1, max_pages, [{page_num, html} | acc])
        else
          Logger.info("📄 No more events found, stopping at page #{page_num - 1}")
          {:ok, Enum.reverse(acc)}
        end

      {:error, :not_found} ->
        # No more pages
        Logger.info("📄 Reached end of pagination at page #{page_num - 1}")
        {:ok, Enum.reverse(acc)}

      {:error, reason} ->
        Logger.error("Failed to fetch page #{page_num}: #{inspect(reason)}")

        if length(acc) > 0 do
          # Return what we have so far
          Logger.warning("⚠️ Returning partial results: #{length(acc)} pages")
          {:ok, Enum.reverse(acc)}
        else
          {:error, reason}
        end
    end
  end

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
    wait_time = Config.rate_limit() * 1000
    Process.sleep(wait_time)
  end

  defp get_redirect_location(response) do
    case get_header(response.headers, "Location") do
      nil -> :error
      location -> {:ok, location}
    end
  end

  defp ensure_utf8(body) when is_binary(body) do
    # Use our new UTF8 utility to ensure valid UTF-8
    # This avoids the latin1 conversion that was corrupting multi-byte sequences
    EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8_with_logging(body, "Karnet HTTP response")
  end

  defp ensure_utf8(body), do: body

  defp get_header(headers, key) do
    headers
    |> Enum.find(fn {k, _} -> String.downcase(k) == String.downcase(key) end)
    |> case do
      {_, value} -> value
      _ -> nil
    end
  end

  defp has_events?(html) do
    # Check if the HTML contains event listings
    # Looking for typical event card elements
    # Also check for specific event content patterns
    String.contains?(html, "class=\"event-item\"") ||
      String.contains?(html, "class=\"wydarzenie\"") ||
      String.contains?(html, "data-event-id") ||
      (String.contains?(html, "href") && String.contains?(html, "/wydarzenia/"))
  end
end
