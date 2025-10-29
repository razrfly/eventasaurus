defmodule EventasaurusWeb.JsonLd.LocalBusinessSchema do
  @moduledoc """
  Generates JSON-LD structured data for venues as LocalBusiness according to schema.org.

  This module converts venue data into properly formatted structured data
  for better SEO and Google rich results for local business listings.

  ## Schema.org LocalBusiness
  - Schema.org LocalBusiness: https://schema.org/LocalBusiness
  - Google Local Business: https://developers.google.com/search/docs/appearance/structured-data/local-business

  ## Venue Types Mapping
  - "venue" → EntertainmentBusiness (theaters, clubs, arenas)
  - "city" → Place (city-wide event locations)
  - "region" → Place (regional event locations)
  """

  require Logger

  alias EventasaurusWeb.UrlHelper

  @doc """
  Generates JSON-LD structured data for a venue as LocalBusiness.

  ## Parameters
    - venue: Venue struct with preloaded associations:
      - :city_ref (with :country)

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> venue = Repo.get(Venue, 1) |> Repo.preload(city_ref: :country)
      iex> EventasaurusWeb.JsonLd.LocalBusinessSchema.generate(venue)
      "{\"@context\":\"https://schema.org\",\"@type\":\"EntertainmentBusiness\",...}"
  """
  def generate(venue) do
    venue
    |> build_business_schema()
    |> Jason.encode!()
  end

  @doc """
  Builds the local business schema map (without JSON encoding).
  Useful for testing or combining with other schemas.
  """
  def build_business_schema(venue) do
    %{
      "@context" => "https://schema.org",
      "@type" => determine_business_type(venue),
      "name" => venue.name,
      "address" => build_address(venue)
    }
    |> add_geo_coordinates(venue)
    |> add_place_id(venue)
    |> add_url(venue)
  end

  # Determine the appropriate schema.org business type based on venue_type
  defp determine_business_type(venue) do
    case venue.venue_type do
      "venue" -> "EntertainmentBusiness"
      "city" -> "Place"
      "region" -> "Place"
      _ -> "Place"
    end
  end

  # Build the postal address according to schema.org
  defp build_address(venue) do
    address = %{
      "@type" => "PostalAddress"
    }

    address =
      if venue.address do
        Map.put(address, "streetAddress", venue.address)
      else
        address
      end

    address =
      if venue.city_ref do
        address
        |> Map.put("addressLocality", venue.city_ref.name)
        |> add_country_info(venue.city_ref)
      else
        address
      end

    address
  end

  defp add_country_info(address, city) do
    if city.country do
      address
      |> Map.put("addressCountry", city.country.code)
    else
      address
    end
  end

  # Add geographic coordinates
  defp add_geo_coordinates(schema, venue) do
    if venue.latitude && venue.longitude do
      Map.put(schema, "geo", %{
        "@type" => "GeoCoordinates",
        "latitude" => venue.latitude,
        "longitude" => venue.longitude
      })
    else
      schema
    end
  end

  # Add Google Place ID if available (from provider_ids)
  defp add_place_id(schema, venue) do
    # Try to get Google Places ID from provider_ids JSONB field
    google_place_id =
      case venue.provider_ids do
        %{"google_places" => id} when is_binary(id) -> id
        %{google_places: id} when is_binary(id) -> id
        _ -> nil
      end

    if google_place_id do
      # Use the Google Maps URL format
      url = "https://www.google.com/maps/place/?q=place_id:#{google_place_id}"
      Map.put(schema, "hasMap", url)
    else
      schema
    end
  end

  # Add venue URL (using slug to build the URL)
  defp add_url(schema, venue) do
    if venue.slug do
      venue_url = UrlHelper.build_url("/venues/#{venue.slug}")
      Map.put(schema, "url", venue_url)
    else
      schema
    end
  end
end
