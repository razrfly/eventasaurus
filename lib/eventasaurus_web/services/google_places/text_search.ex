defmodule EventasaurusWeb.Services.GooglePlaces.TextSearch do
  @moduledoc """
  Handles Google Places Text Search API for finding places/venues.
  Used for general place searches with natural language queries.
  """

  alias EventasaurusWeb.Services.GooglePlaces.Client
  require Logger

  @base_url "https://maps.googleapis.com/maps/api/place/textsearch/json"

  @doc """
  Searches for places using the Text Search API.
  """
  def search(query, options \\ %{}) do
    api_key = Client.get_api_key()

    if api_key do
      url = build_url(query, api_key, options)
      
      case Client.get_json(url) do
        {:ok, %{"results" => results, "status" => "OK"}} ->
          {:ok, results}
        
        {:ok, %{"results" => [], "status" => "ZERO_RESULTS"}} ->
          {:ok, []}
        
        {:ok, %{"status" => status, "error_message" => message}} ->
          Logger.error("Google Places Text Search API error: #{status} - #{message}")
          {:error, "API error: #{status}"}
        
        {:ok, %{"status" => status}} ->
          Logger.error("Google Places Text Search API returned status: #{status}")
          {:error, "API returned status: #{status}"}
        
        {:error, reason} ->
          Logger.error("Google Places Text Search failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, "No API key configured"}
    end
  end

  defp build_url(query, api_key, _options) do
    params = %{
      query: query,
      key: api_key
    }

    "#{@base_url}?#{URI.encode_query(params)}"
  end
end