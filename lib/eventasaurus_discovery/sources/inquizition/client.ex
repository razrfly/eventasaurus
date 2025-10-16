defmodule EventasaurusDiscovery.Sources.Inquizition.Client do
  @moduledoc """
  HTTP client for fetching venue data from StoreLocatorWidgets CDN.

  Handles:
  - HTTP requests to CDN endpoint
  - JSONP wrapper stripping (slw(...) → {...})
  - Exponential backoff retry logic
  - Timeout management
  - Error handling and logging

  ## Example

      iex> Client.fetch_venues()
      {:ok, %{"stores" => [%{"storeid" => "97520779", ...}], ...}}

      iex> Client.fetch_venues()
      {:error, :timeout}
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Inquizition.Config

  @doc """
  Fetches all venues from StoreLocatorWidgets CDN endpoint.

  Returns `{:ok, parsed_data}` with the complete response including:
  - `stores`: Array of venue objects
  - `settings`: Widget configuration
  - `markers`: Map marker settings
  - `filters`: Day-of-week filters

  Returns `{:error, reason}` on failure after all retries exhausted.

  ## Examples

      iex> Client.fetch_venues()
      {:ok, %{
        "stores" => [
          %{
            "storeid" => "97520779",
            "name" => "Andrea Ludgate Hill",
            "data" => %{
              "address" => "47 Ludgate Hill\\r\\nLondon\\r\\nEC4M 7JZ",
              "description" => "Tuesdays, 6.30pm",
              "map_lat" => "51.513898",
              "map_lng" => "-0.1026125"
            },
            "filters" => ["Tuesday"],
            "timezone" => "Europe/London",
            "country" => "GB"
          }
        ],
        "settings" => %{...},
        "markers" => %{...}
      }}
  """
  def fetch_venues do
    url = Config.cdn_url()

    Logger.info("[Inquizition] Fetching venues from CDN: #{url}")

    fetch_with_retry(url, Config.max_retries())
  end

  # Private functions

  defp fetch_with_retry(url, retries_left, attempt \\ 1) do
    case make_request(url) do
      {:ok, body} ->
        parse_jsonp_response(body)

      {:error, reason} when retries_left > 0 ->
        delay = calculate_backoff_delay(attempt)
        Logger.warning(
          "[Inquizition] Request failed (attempt #{attempt}), retrying in #{delay}ms: #{inspect(reason)}"
        )
        Process.sleep(delay)
        fetch_with_retry(url, retries_left - 1, attempt + 1)

      {:error, reason} ->
        Logger.error("[Inquizition] All retry attempts exhausted: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp make_request(url) do
    opts = [
      timeout: Config.timeout(),
      recv_timeout: Config.timeout(),
      follow_redirect: true,
      max_redirect: 3
    ]

    case HTTPoison.get(url, Config.headers(), opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} when is_binary(body) and body != "" ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("[Inquizition] CDN returned status #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_error, reason}}
    end
  end

  defp parse_jsonp_response(body) do
    # Strip JSONP wrapper: slw({...}) → {...}
    json_string =
      body
      |> String.trim()
      |> String.replace_prefix("slw(", "")
      |> String.replace_suffix(")", "")
      |> String.trim()

    case Jason.decode(json_string) do
      {:ok, data} when is_map(data) ->
        # Validate response structure
        if Map.has_key?(data, "stores") do
          store_count = length(Map.get(data, "stores", []))
          Logger.info("[Inquizition] Successfully fetched #{store_count} venues from CDN")
          {:ok, data}
        else
          Logger.error("[Inquizition] Invalid response structure: missing 'stores' key")
          {:error, :invalid_response_structure}
        end

      {:ok, _non_map} ->
        Logger.error("[Inquizition] Invalid JSON: expected object, got non-map")
        {:error, :invalid_json_structure}

      {:error, reason} ->
        Logger.error("[Inquizition] JSON parsing failed: #{inspect(reason)}")
        {:error, {:json_parse_error, reason}}
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
