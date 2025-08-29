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

  defp build_url(query, api_key, options) do
    params = 
      %{
        input: query,
        key: api_key
      }
      |> maybe_put(:types, Map.get(options, :types, "(cities)"))  # Default to cities
      |> maybe_put(:language, Map.get(options, :language))
      |> maybe_put(:components, Map.get(options, :components))
      |> maybe_put(:location, format_location(Map.get(options, :location)))
      |> maybe_put(:radius, Map.get(options, :radius))
      |> maybe_put(:strictbounds, Map.get(options, :strictbounds))
      |> maybe_put(:sessiontoken, Map.get(options, :session_token) || Map.get(options, :sessiontoken))

    "#{@base_url}?#{URI.encode_query(params)}"
  end
  
  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
  
  defp format_location({lat, lng}) when is_number(lat) and is_number(lng), do: "#{lat},#{lng}"
  defp format_location(_), do: nil
end