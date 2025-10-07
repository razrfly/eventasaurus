defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.VenueEnricher do
  @moduledoc """
  Handles venue coordinate enrichment for Resident Advisor events.

  Since RA's GraphQL API does not provide venue coordinates, this module
  implements a multi-strategy approach to obtain them:

  1. Try venue detail GraphQL query (if available)
  2. Fallback to Google Places API geocoding
  3. Last resort: city center coordinates with needs_geocoding flag

  This follows the proven pattern from the Karnet scraper.
  """

  require Logger
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Client

  @doc """
  Get coordinates for a venue.

  Follows the Cinema City pattern: try to get coordinates from RA's GraphQL API.
  If not available, return nil and let VenueProcessor handle Google Places lookup.

  ## Parameters
  - `venue_id` - RA venue ID
  - `venue_name` - Venue name for logging
  - `city_context` - City struct (unused, for interface compatibility)

  ## Returns
  Tuple of `{latitude, longitude, needs_geocoding_flag}`
  - Returns {lat, lng, false} if RA provides coordinates
  - Returns {nil, nil, false} otherwise (VenueProcessor will geocode)

  ## Examples

      iex> VenueEnricher.get_coordinates("12345", "Smolna", city)
      {nil, nil, false}  # VenueProcessor will handle geocoding
  """
  def get_coordinates(venue_id, venue_name, _city_context) do
    # Strategy 1: Try venue detail GraphQL query
    case try_venue_detail_query(venue_id) do
      %{latitude: lat, longitude: lng} ->
        Logger.debug("✅ Got coordinates from RA venue detail query for #{venue_name}")
        {lat, lng, false}

      nil ->
        # RA doesn't provide coordinates
        # Return nil and let VenueProcessor handle Google Places lookup
        # This follows the same pattern as Cinema City scraper
        Logger.debug(
          "RA doesn't provide coordinates for #{venue_name}, deferring to VenueProcessor"
        )

        {nil, nil, false}
    end
  end

  # Private functions

  defp try_venue_detail_query(venue_id) do
    case Client.fetch_venue_details(venue_id) do
      {:ok, %{"latitude" => lat, "longitude" => lng}}
      when not is_nil(lat) and not is_nil(lng) ->
        %{latitude: to_float(lat), longitude: to_float(lng)}

      {:ok, venue} ->
        Logger.debug("Venue detail query succeeded but no coordinates: #{inspect(venue)}")
        nil

      {:error, :venue_query_not_supported} ->
        Logger.debug("RA venue detail query not supported")
        nil

      {:error, reason} ->
        Logger.debug("Venue detail query failed: #{inspect(reason)}")
        nil
    end
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      # Return nil instead of 0.0 for invalid coordinates
      # 0.0 is a valid coordinate (Gulf of Guinea) and shouldn't be a fallback
      :error -> nil
    end
  end

  # Return nil instead of 0.0 for non-numeric values
  # Prevents treating invalid data as valid coordinates
  defp to_float(_), do: nil
end
