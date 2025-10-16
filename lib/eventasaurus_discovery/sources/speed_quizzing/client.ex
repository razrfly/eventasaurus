defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Client do
  @moduledoc """
  HTTP client for fetching venue and event data from Speed Quizzing.

  Handles:
  - HTTP requests to index and detail pages
  - Exponential backoff retry logic
  - Timeout management
  - Error handling and logging

  ## Example

      iex> Client.fetch_index()
      {:ok, html_body}

      iex> Client.fetch_event_details("12345")
      {:ok, html_body}
  """

  require Logger
  alias EventasaurusDiscovery.Sources.SpeedQuizzing.Config

  @doc """
  Fetches the index page containing the event list.

  Returns the raw HTML body which contains embedded JSON.
  """
  def fetch_index do
    url = Config.index_url()
    Logger.info("[SpeedQuizzing] Fetching index page: #{url}")
    fetch_with_retry(url, Config.max_retries())
  end

  @doc """
  Fetches a specific event detail page.
  """
  def fetch_event_details(event_id) do
    url = Config.event_url_format() |> String.replace("{event_id}", "#{event_id}")
    Logger.info("[SpeedQuizzing] Fetching event details for ID: #{event_id}")
    fetch_with_retry(url, Config.max_retries())
  end

  # Private functions

  defp fetch_with_retry(url, retries_left, attempt \\ 1) do
    case make_request(url) do
      {:ok, body} ->
        {:ok, body}

      {:error, reason} when retries_left > 0 ->
        delay = calculate_backoff_delay(attempt)

        Logger.warning(
          "[SpeedQuizzing] Request failed (attempt #{attempt}), retrying in #{delay}ms: #{inspect(reason)}"
        )

        Process.sleep(delay)
        fetch_with_retry(url, retries_left - 1, attempt + 1)

      {:error, reason} ->
        Logger.error("[SpeedQuizzing] All retry attempts exhausted: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp make_request(url) do
    # Use empty headers like trivia_advisor - custom headers may affect response
    headers = []

    opts = [
      timeout: Config.timeout(),
      recv_timeout: Config.timeout(),
      follow_redirect: true,
      max_redirect: 3
    ]

    case HTTPoison.get(url, headers, opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}}
      when is_binary(body) and body != "" ->
        {:ok, body}

      # 404 Not Found - event page deleted (stale index data)
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.warning("[SpeedQuizzing] Event page not found (stale index data): #{url}")
        {:error, :event_not_found}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("[SpeedQuizzing] Server returned status #{status}")
        {:error, {:http_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("[SpeedQuizzing] HTTP request failed: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp calculate_backoff_delay(attempt) do
    # Exponential backoff: 500ms, 1000ms, 2000ms
    base_delay = Config.retry_delay_ms()
    delay = base_delay * :math.pow(2, attempt - 1)

    # Cap at 5 seconds
    min(round(delay), 5000)
  end
end
