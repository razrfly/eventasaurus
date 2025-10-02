defmodule EventasaurusDiscovery.Sources.KinoKrakow.Extractors.CinemaExtractor do
  @moduledoc """
  Extracts cinema venue data for Kino Krakow.

  Since Kino Krakow does not provide individual cinema info pages or GPS coordinates,
  this module returns cinema name formatted from the slug along with city and country.

  VenueProcessor automatically geocodes venues without coordinates using Google Maps API.

  Extracts:
  - Cinema name (formatted from slug)
  - City ("Kraków")
  - Country ("Poland")
  - Coordinates set to nil (triggers automatic geocoding)
  """

  require Logger

  @doc """
  Extract cinema venue data from cinema slug.

  Note: Kino Krakow website does not provide individual cinema pages or GPS coordinates.
  Returns cinema name with city/country for automatic geocoding via VenueProcessor.

  Returns map with:
  - name: String (formatted from slug)
  - city: String ("Kraków")
  - country: String ("Poland")
  - latitude: nil (triggers VenueGeocoder to geocode via Google Maps API)
  - longitude: nil (triggers VenueGeocoder to geocode via Google Maps API)
  """
  def extract(_html, cinema_slug) when is_binary(cinema_slug) do
    %{
      name: format_name_from_slug(cinema_slug),
      city: "Kraków",
      country: "Poland",
      latitude: nil,
      longitude: nil
    }
  end

  # Format cinema name from slug (e.g., "kino-pod-baranami" -> "Kino Pod Baranami")
  defp format_name_from_slug(slug) do
    slug
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
