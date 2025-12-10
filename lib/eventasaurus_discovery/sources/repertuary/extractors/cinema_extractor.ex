defmodule EventasaurusDiscovery.Sources.Repertuary.Extractors.CinemaExtractor do
  @moduledoc """
  Extracts cinema venue data for Repertuary.pl cinema network.

  Since Repertuary.pl does not provide individual cinema info pages or GPS coordinates,
  this module returns cinema name formatted from the slug along with city and country.

  VenueProcessor automatically looks up venues using Google Places API (TextSearch + Details).

  ## Multi-City Support

  Pass the city key to get city-specific venue data:

      CinemaExtractor.extract("", "kino-pod-baranami", "krakow")
      # => %{name: "Kino Pod Baranami", city: "Kraków", country: "Poland", ...}

      CinemaExtractor.extract("", "cinema-city-arkadia", "warszawa")
      # => %{name: "Cinema City Arkadia", city: "Warszawa", country: "Poland", ...}

  Extracts:
  - Cinema name (formatted from slug)
  - City (from Cities configuration)
  - Country ("Poland")
  - Coordinates set to nil (triggers automatic Google Places lookup)
  """

  require Logger

  alias EventasaurusDiscovery.Sources.Repertuary.{Config, Cities}

  @doc """
  Extract cinema venue data from cinema slug.

  Note: Repertuary.pl website does not provide individual cinema pages or GPS coordinates.
  Returns cinema name with city/country for automatic lookup via VenueProcessor.

  ## Parameters
  - html: HTML content (not used, kept for interface compatibility)
  - cinema_slug: The cinema's URL slug
  - city: City key (e.g., "krakow", "warszawa"). Defaults to "krakow".

  Returns map with:
  - name: String (formatted from slug)
  - city: String (from Cities configuration)
  - country: String ("Poland")
  - latitude: nil (triggers Google Places API lookup via VenueProcessor)
  - longitude: nil (triggers Google Places API lookup via VenueProcessor)
  """
  def extract(_html, cinema_slug, city \\ Config.default_city()) when is_binary(cinema_slug) do
    city_config = Cities.get(city) || Cities.get(Config.default_city())

    %{
      name: format_name_from_slug(cinema_slug),
      city: city_config.name,
      country: city_config.country,
      latitude: nil,
      longitude: nil
    }
  end

  # Format cinema name from slug (e.g., "kino-pod-baranami" -> "Kino Pod Baranami")
  # Also handles slashes: "cinema-city/kazimierz" -> "Cinema City Kazimierz"
  defp format_name_from_slug(slug) do
    slug
    |> String.replace("-", " ")
    |> String.replace("/", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
