defmodule EventasaurusDiscovery.Sources.Waw4free.Client do
  @moduledoc """
  HTTP client for fetching content from waw4free.pl website.

  Handles:
  - Rate limiting (2 seconds between requests)
  - Retries with exponential backoff
  - Polish character encoding (UTF-8)
  - Error handling
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Waw4free.Config

  @doc """
  Fetch HTML content from a given URL with rate limiting and retries.
  """
  def fetch_page(url, opts \\ []) do
    retries = Keyword.get(opts, :retries, 3)
    attempt = Keyword.get(opts, :attempt, 1)

    # Apply rate limiting (except on first request)
    if attempt > 1 and not Keyword.get(opts, :skip_rate_limit, false) do
      apply_rate_limit()
    end

    Logger.debug("🌐 Fetching waw4free page: #{url} (attempt #{attempt}/#{retries})")

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

  # Private functions

  defp apply_rate_limit do
    # Wait for configured rate limit (2 seconds by default)
    rate_limit_ms = Config.rate_limit() * 1000
    Process.sleep(rate_limit_ms)
  end

  defp retry_request(_url, _opts, retries, attempt) when attempt >= retries do
    Logger.error("❌ Max retries (#{retries}) reached")
    {:error, :max_retries_reached}
  end

  defp retry_request(url, opts, _retries, attempt) do
    # Exponential backoff: 2^attempt seconds
    backoff_ms = (:math.pow(2, attempt) * 1000) |> round()
    Logger.debug("⏳ Waiting #{backoff_ms}ms before retry...")
    Process.sleep(backoff_ms)

    # Retry with incremented attempt counter
    fetch_page(url, Keyword.put(opts, :attempt, attempt + 1))
  end

  defp get_header(headers, key) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(k) == String.downcase(key) end)
    |> case do
      {_k, v} -> v
      nil -> nil
    end
  end

  defp get_redirect_location(response) do
    case get_header(response.headers, "location") do
      nil -> :error
      location -> {:ok, location}
    end
  end

  defp ensure_utf8(binary) when is_binary(binary) do
    # Ensure the binary is valid UTF-8
    # If it's not, try to fix it
    case :unicode.characters_to_binary(binary, :utf8, :utf8) do
      {:error, _, _} ->
        # Try latin1 to utf8 conversion (common for Polish content)
        case :unicode.characters_to_binary(binary, :latin1, :utf8) do
          result when is_binary(result) -> result
          _ -> binary
        end

      result when is_binary(result) ->
        result

      _ ->
        binary
    end
  end
end
