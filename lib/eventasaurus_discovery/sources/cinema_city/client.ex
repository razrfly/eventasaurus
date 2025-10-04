defmodule EventasaurusDiscovery.Sources.CinemaCity.Client do
  @moduledoc """
  HTTP client for Cinema City JSON API.

  Handles:
  - Rate limiting
  - Retries with exponential backoff
  - JSON parsing
  - Error handling
  - Polish character encoding (UTF-8)
  """

  require Logger
  alias EventasaurusDiscovery.Sources.CinemaCity.Config

  @doc """
  Fetch cinema list from API.

  Returns {:ok, cinemas} where cinemas is a list of cinema maps, or {:error, reason}.

  ## Example Response Structure
  ```json
  {
    "body": {
      "cinemas": [
        {
          "id": "1088",
          "displayName": "Kraków - Bonarka",
          "city": "Kraków",
          ...
        }
      ]
    }
  }
  ```
  """
  def fetch_cinema_list(until_date, opts \\ []) do
    url = Config.cinema_list_url(until_date)

    Logger.info("📍 Fetching Cinema City cinema list (until: #{until_date})")

    case fetch_json(url, opts) do
      {:ok, %{"body" => %{"cinemas" => cinemas}}} when is_list(cinemas) ->
        Logger.info("✅ Found #{length(cinemas)} Cinema City locations")
        {:ok, cinemas}

      {:ok, response} ->
        Logger.error("❌ Unexpected cinema list response structure: #{inspect(response)}")
        {:error, :invalid_response_structure}

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch cinema list: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetch film events for a specific cinema and date.

  Returns {:ok, %{films: [...], events: [...]}} or {:error, reason}.

  ## Example Response Structure
  ```json
  {
    "body": {
      "films": [
        {
          "id": "7592s3r",
          "name": "Avatar: Istota wody",
          "length": 192,
          ...
        }
      ],
      "events": [
        {
          "id": "123456",
          "filmId": "7592s3r",
          "eventDateTime": "2025-10-03T19:30:00",
          ...
        }
      ]
    }
  }
  ```
  """
  def fetch_film_events(cinema_id, date, opts \\ []) do
    url = Config.film_events_url(cinema_id, date)

    Logger.debug("🎬 Fetching film events for cinema #{cinema_id} on #{date}")

    case fetch_json(url, opts) do
      {:ok, %{"body" => %{"films" => films, "events" => events}}}
      when is_list(films) and is_list(events) ->
        Logger.debug("✅ Found #{length(films)} films, #{length(events)} events")
        {:ok, %{films: films, events: events}}

      {:ok, %{"body" => body}} ->
        # Handle case where API returns empty or partial data
        films = Map.get(body, "films", [])
        events = Map.get(body, "events", [])

        Logger.debug("⚠️ Partial data: #{length(films)} films, #{length(events)} events")
        {:ok, %{films: films, events: events}}

      {:ok, response} ->
        Logger.error("❌ Unexpected film events response structure: #{inspect(response)}")
        {:error, :invalid_response_structure}

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch film events: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetch and parse JSON from a URL with rate limiting and retries.
  """
  def fetch_json(url, opts \\ []) do
    retries = Keyword.get(opts, :retries, Config.max_retries())
    attempt = Keyword.get(opts, :attempt, 1)

    # Apply rate limiting (except on first request or if explicitly skipped)
    if attempt == 1 && !Keyword.get(opts, :skip_rate_limit, false) do
      apply_rate_limit()
    end

    Logger.debug("🌐 Fetching Cinema City API: #{url} (attempt #{attempt}/#{retries})")

    case HTTPoison.get(url, Config.headers(),
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_json_response(body)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.warning("❌ API endpoint not found: #{url}")
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: status_code} = response}
      when status_code in 301..302 ->
        # Handle redirects
        case get_redirect_location(response) do
          {:ok, redirect_url} ->
            Logger.info("↪️ Following redirect: #{redirect_url}")
            fetch_json(redirect_url, Keyword.put(opts, :skip_rate_limit, true))

          :error ->
            {:error, :redirect_failed}
        end

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        # Rate limited - wait longer and retry
        Logger.warning("⏳ Rate limited by Cinema City API, waiting 30s...")
        Process.sleep(30_000)
        retry_request(url, opts, retries, attempt)

      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code >= 500 ->
        # Server error - retry with backoff
        Logger.warning("⚠️ Cinema City API server error (#{status_code}), retrying...")
        retry_request(url, opts, retries, attempt)

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("❌ Unexpected status code: #{status_code}, body: #{String.slice(body, 0, 200)}")
        {:error, {:unexpected_status, status_code}}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Request timeout, retrying...")
        retry_request(url, opts, retries, attempt)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ HTTP error: #{inspect(reason)}")
        retry_request(url, opts, retries, attempt)
    end
  end

  # Parse JSON response body
  defp parse_json_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, json} ->
        {:ok, json}

      {:error, %Jason.DecodeError{} = error} ->
        Logger.error("❌ Failed to parse JSON response: #{inspect(error)}")
        Logger.debug("Response body: #{String.slice(body, 0, 500)}")
        {:error, :invalid_json}
    end
  end

  # Retry logic with exponential backoff
  defp retry_request(url, opts, retries, attempt) when attempt < retries do
    # Exponential backoff: 2^attempt seconds
    wait_time = :math.pow(2, attempt) |> round() |> Kernel.*(1000)
    Logger.info("⏳ Waiting #{wait_time}ms before retry...")
    Process.sleep(wait_time)

    fetch_json(url, Keyword.merge(opts, retries: retries, attempt: attempt + 1))
  end

  defp retry_request(_url, _opts, _retries, _attempt) do
    {:error, :max_retries_exceeded}
  end

  # Apply rate limiting
  defp apply_rate_limit do
    wait_time = Config.rate_limit() * 1000
    Process.sleep(wait_time)
  end

  # Extract redirect location from response headers
  defp get_redirect_location(response) do
    case get_header(response.headers, "Location") do
      nil -> :error
      location -> {:ok, location}
    end
  end

  # Get header value (case-insensitive)
  defp get_header(headers, key) do
    headers
    |> Enum.find(fn {k, _} -> String.downcase(k) == String.downcase(key) end)
    |> case do
      {_, value} -> value
      _ -> nil
    end
  end
end
