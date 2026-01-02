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

  alias EventasaurusWeb.JsonLd.Helpers
  alias EventasaurusWeb.UrlHelper

  @doc """
  Generates JSON-LD structured data for a venue as LocalBusiness.

  ## Parameters
    - venue: Venue struct with preloaded associations:
      - :city_ref (with :country)
    - opts: Optional keyword list:
      - :request_uri - URI struct from request context for correct URL generation

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> venue = Repo.get(Venue, 1) |> Repo.preload(city_ref: :country)
      iex> EventasaurusWeb.JsonLd.LocalBusinessSchema.generate(venue)
      "{\"@context\":\"https://schema.org\",\"@type\":\"EntertainmentBusiness\",...}"
  """
  def generate(venue, opts \\ []) do
    venue
    |> build_business_schema(opts)
    |> Jason.encode!()
  end

  @doc """
  Builds the local business schema map (without JSON encoding).
  Useful for testing or combining with other schemas.

  ## Options
    - :request_uri - URI struct from request context for correct URL generation
  """
  def build_business_schema(venue, opts \\ []) do
    request_uri = Keyword.get(opts, :request_uri)

    %{
      "@context" => "https://schema.org",
      "@type" => determine_business_type(venue),
      "name" => venue.name,
      "address" => build_address(venue)
    }
    |> Helpers.add_geo_coordinates(venue)
    |> add_url(venue, request_uri)
    |> add_same_as(venue, request_uri)
    |> add_has_map(venue)
    |> add_opening_hours(venue)
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

  # Build the canonical venue URL using flat /venues/:slug path
  # Issue #3143: Simplified from city-scoped /c/:city/venues/:slug
  defp build_venue_url(venue, request_uri) do
    if venue.slug do
      path = "/venues/#{venue.slug}"
      UrlHelper.build_url(path, request_uri)
    else
      nil
    end
  end

  # Add venue URL (using flat /venues/:slug canonical URL)
  defp add_url(schema, venue, request_uri) do
    case build_venue_url(venue, request_uri) do
      nil -> schema
      url -> Map.put(schema, "url", url)
    end
  end

  # Add sameAs property linking to our own canonical URL
  # Per schema.org, sameAs indicates the item is the same as a resource at the URL
  defp add_same_as(schema, venue, request_uri) do
    case build_venue_url(venue, request_uri) do
      nil -> schema
      url -> Map.put(schema, "sameAs", [url])
    end
  end

  # Add hasMap property using Google Place ID or coordinates
  defp add_has_map(schema, venue) do
    cond do
      # First try Google Places ID
      google_place_id = get_google_place_id(venue) ->
        url = "https://www.google.com/maps/place/?q=place_id:#{google_place_id}"
        Map.put(schema, "hasMap", url)

      # Fall back to coordinates if available
      venue.latitude && venue.longitude ->
        url =
          "https://www.google.com/maps/search/?api=1&query=#{venue.latitude},#{venue.longitude}"

        Map.put(schema, "hasMap", url)

      true ->
        schema
    end
  end

  # Extract Google Places ID from provider_ids JSONB field
  defp get_google_place_id(venue) do
    case Map.get(venue, :provider_ids) || Map.get(venue, "provider_ids") do
      %{"google_places" => id} when is_binary(id) -> id
      %{google_places: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  # Add opening hours if available in venue data
  defp add_opening_hours(schema, venue) do
    case Map.get(venue, :opening_hours) || Map.get(venue, "opening_hours") do
      hours when is_list(hours) and length(hours) > 0 ->
        Map.put(schema, "openingHours", hours)

      hours when is_binary(hours) and hours != "" ->
        Map.put(schema, "openingHours", hours)

      _ ->
        schema
    end
  end
end
