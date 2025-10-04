defmodule EventasaurusWeb.Services.GooglePlaces.VenuePlacesAdapter do
  @moduledoc """
  Adapter for extracting venue data from Google Places API results.

  This module provides a consistent interface for transforming Google Places API
  responses into venue data structures used by the discovery system.

  Follows the same pattern as GooglePlacesDataAdapter used by private events,
  ensuring consistency across the application.
  """

  require Logger

  @doc """
  Extracts venue data from Google Places API result.

  ## Parameters
    - place_data: Map containing Google Places API result

  ## Returns
    Map with venue data:
    - name: Official Google venue name
    - address: Formatted address
    - city: City name (extracted from address components)
    - country: Country name (extracted from address components)
    - latitude: Latitude coordinate
    - longitude: Longitude coordinate
    - place_id: Google Place ID
    - phone: Phone number (if available)
    - website: Website URL (if available)
    - rating: Google rating (if available)
    - metadata: Additional metadata

  ## Example
      place_data = %{
        "name" => "Kino Pod Baranami",
        "formatted_address" => "Rynek Główny 27, 31-010 Kraków, Poland",
        "geometry" => %{"location" => %{"lat" => 50.061947, "lng" => 19.937508}},
        "place_id" => "ChIJ...",
        ...
      }

      VenuePlacesAdapter.extract_venue_data(place_data)
      # => %{name: "Kino Pod Baranami", latitude: 50.061947, ...}
  """
  def extract_venue_data(place_data) when is_map(place_data) do
    # Extract coordinates
    {latitude, longitude} = extract_coordinates(place_data)

    # Extract address components
    address_components = Map.get(place_data, "address_components", [])

    %{
      name: extract_name(place_data),
      address: extract_address(place_data),
      city: extract_city(address_components),
      country: extract_country(address_components),
      latitude: latitude,
      longitude: longitude,
      place_id: Map.get(place_data, "place_id"),
      phone: Map.get(place_data, "formatted_phone_number"),
      website: Map.get(place_data, "website"),
      rating: Map.get(place_data, "rating"),
      metadata: extract_metadata(place_data)
    }
  end

  # Extract venue name following GooglePlacesDataAdapter pattern
  # Reference: lib/eventasaurus_web/live/components/adapters/google_places_data_adapter.ex:83-84
  defp extract_name(place_data) do
    place_data["name"] || place_data["title"] || "Unknown Place"
  end

  # Extract formatted address
  defp extract_address(place_data) do
    # Prefer vicinity (shorter) over formatted_address for cleaner display
    place_data["vicinity"] || place_data["formatted_address"]
  end

  # Extract coordinates from geometry
  defp extract_coordinates(place_data) do
    case get_in(place_data, ["geometry", "location"]) do
      %{"lat" => lat, "lng" => lng} when is_number(lat) and is_number(lng) ->
        {lat, lng}

      _ ->
        Logger.warning("No valid coordinates in Google Places result")
        {nil, nil}
    end
  end

  # Extract city from address components
  defp extract_city(address_components) when is_list(address_components) do
    # Try locality first, then administrative_area_level_2
    find_component(address_components, "locality") ||
      find_component(address_components, "administrative_area_level_2")
  end

  defp extract_city(_), do: nil

  # Extract country from address components
  defp extract_country(address_components) when is_list(address_components) do
    find_component(address_components, "country")
  end

  defp extract_country(_), do: nil

  # Find address component by type
  defp find_component(components, type) do
    components
    |> Enum.find(fn component ->
      types = Map.get(component, "types", [])
      type in types
    end)
    |> case do
      %{"long_name" => name} -> name
      _ -> nil
    end
  end

  # Extract additional metadata
  defp extract_metadata(place_data) do
    %{
      types: Map.get(place_data, "types", []),
      business_status: Map.get(place_data, "business_status"),
      user_ratings_total: Map.get(place_data, "user_ratings_total"),
      price_level: Map.get(place_data, "price_level"),
      opening_hours: extract_opening_hours(place_data)
    }
  end

  # Extract opening hours
  defp extract_opening_hours(place_data) do
    case get_in(place_data, ["opening_hours", "weekday_text"]) do
      hours when is_list(hours) -> hours
      _ -> nil
    end
  end
end
