defmodule EventasaurusWeb.Services.GooglePlaces.Autocomplete do
  @moduledoc """
  Handles Google Places Autocomplete API for city searches.
  Uses type filtering to get only city results.
  """

  alias EventasaurusWeb.Services.GooglePlaces.Client
  require Logger

  @base_url "https://maps.googleapis.com/maps/api/place/autocomplete/json"

  @doc """
  Searches for cities using the Autocomplete API with (cities) type.
  """
  def search_cities(query, options \\ %{}) do
    api_key = Client.get_api_key()

    if api_key do
      url = build_url(query, api_key, options)
      
      case Client.get_json(url) do
        {:ok, %{"predictions" => predictions, "status" => "OK"}} ->
          {:ok, predictions}
        
        {:ok, %{"predictions" => [], "status" => "ZERO_RESULTS"}} ->
          {:ok, []}
        
        {:ok, %{"status" => status, "error_message" => message}} ->
          Logger.error("Google Places Autocomplete API error: #{status} - #{message}")
          {:error, "API error: #{status}"}
        
        {:ok, %{"status" => status}} ->
          Logger.error("Google Places Autocomplete API returned status: #{status}")
          {:error, "API returned status: #{status}"}
        
        {:error, reason} ->
          Logger.error("Google Places Autocomplete failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, "No API key configured"}
    end
  end

  defp build_url(query, api_key, _options) do
    params = %{
      input: query,
      types: "(cities)",  # Filter for cities only
      key: api_key
    }

    "#{@base_url}?#{URI.encode_query(params)}"
  end
end