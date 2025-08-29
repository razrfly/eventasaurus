defmodule EventasaurusWeb.Services.GooglePlacesRichDataProvider do
  @moduledoc """
  Rich data provider for Google Places API integration.
  Acts as an orchestrator for the modular Google Places API components.
  """

  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour

  alias EventasaurusWeb.Services.GooglePlaces.{
    Client,
    TextSearch,
    Autocomplete,
    Geocoding,
    Details,
    Photos,
    Normalizer
  }

  require Logger

  @impl true
  def provider_id, do: :google_places

  @impl true
  def provider_name, do: "Google Places"

  @impl true
  def supported_types, do: [:venue, :restaurant, :activity]

  @impl true
  def search(query, options \\ %{}) do
    location_scope = Map.get(options, :location_scope, "place")
    
    result = case location_scope do
      "city" ->
        search_cities(query, options)
      
      "region" ->
        search_regions(query, options)
      
      "country" ->
        search_countries(query, options)
      
      _ ->
        search_places(query, options)
    end

    case result do
      {:ok, results} -> {:ok, results}
      {:error, reason} ->
        Logger.warning("Google Places search failed: #{inspect(reason)}")
        {:error, :api_error}
    end
  end

  @impl true
  def get_details(_provider_id, content_id, _content_type, options \\ %{}) do
    # Use existing fetch_rich_data functionality
    external_data = %{"place_id" => content_id}
    case fetch_rich_data(external_data, Enum.into(options, [])) do
      {:ok, rich_data} -> {:ok, rich_data}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_cached_details(_provider_id, content_id, _content_type, _options \\ %{}) do
    cache_key = "place_details_#{content_id}"
    case Cachex.get(Client.cache_name(), cache_key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, cached_data} -> {:ok, cached_data}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def validate_config do
    case Client.get_api_key() do
      nil -> {:error, "Google Places API key not configured"}
      _key -> :ok
    end
  end

  def can_handle?(external_data) when is_map(external_data) do
    # Check for Google Places specific fields
    has_place_id = Map.has_key?(external_data, "place_id")
    has_google_fields = Map.has_key?(external_data, "formatted_address") or
                       Map.has_key?(external_data, "geometry") or
                       Map.has_key?(external_data, "rating")

    has_place_id and has_google_fields
  end

  def can_handle?(_), do: false

  def fetch_rich_data(external_data, opts \\ []) do
    place_id = Map.get(external_data, "place_id")
    
    with {:ok, enhanced_data} <- fetch_enhanced_place_details(place_id, external_data, opts),
         {:ok, processed_data} <- Normalizer.process_place_data(enhanced_data, opts) do
      {:ok, processed_data}
    else
      {:error, :rate_limited} ->
        Logger.warning("Google Places API rate limited")
        {:ok, Normalizer.create_fallback_data(external_data)}

      {:error, reason} ->
        Logger.error("Failed to fetch Google Places data: #{inspect(reason)}")
        {:ok, Normalizer.create_fallback_data(external_data)}
    end
  end

  # Private functions for different search types

  defp search_places(query, _options) do
    case TextSearch.search(query) do
      {:ok, results} ->
        normalized = Enum.map(results, &Normalizer.normalize_search_result/1)
        {:ok, normalized}
      error ->
        error
    end
  end

  defp search_cities(query, _options) do
    case Autocomplete.search_cities(query) do
      {:ok, predictions} ->
        normalized = Enum.map(predictions, &Normalizer.normalize_autocomplete_prediction/1)
        {:ok, normalized}
      error ->
        error
    end
  end

  defp search_regions(query, options) do
    options_with_type = Map.put(options, :type, "region")
    case Geocoding.search(query, options_with_type) do
      {:ok, results} ->
        normalized = Enum.map(results, &Normalizer.normalize_geocoding_result/1)
        {:ok, normalized}
      error ->
        error
    end
  end

  defp search_countries(query, options) do
    options_with_type = Map.put(options, :type, "country")
    case Geocoding.search(query, options_with_type) do
      {:ok, results} ->
        normalized = Enum.map(results, &Normalizer.normalize_geocoding_result/1)
        {:ok, normalized}
      error ->
        error
    end
  end

  defp fetch_enhanced_place_details(place_id, external_data, opts) do
    case Details.fetch(place_id, opts) do
      {:ok, enhanced_data} ->
        # Merge original data with enhanced data
        merged_data = Map.merge(external_data, enhanced_data)
        {:ok, merged_data}

      {:error, reason} ->
        Logger.warning("Failed to fetch enhanced place details: #{inspect(reason)}")
        {:ok, external_data}  # Fallback to original data
    end
  end
end