defmodule EventasaurusWeb.JsonLd.CitySchema do
  @moduledoc """
  Generates JSON-LD structured data for city pages according to schema.org and Google guidelines.

  This module converts city data into properly formatted structured data
  for better SEO and Google rich results.

  ## Schema.org Types
  - schema.org/City
  - schema.org/Place

  ## References
  - Schema.org Place: https://schema.org/Place
  - Schema.org City: https://schema.org/City
  - Google Rich Results: https://developers.google.com/search/docs/appearance/structured-data
  """

  alias Eventasaurus.CDN
  alias EventasaurusWeb.UrlHelper

  @doc """
  Generates JSON-LD structured data for a city page.

  ## Parameters
    - city: City struct with preloaded :country association
    - stats: Map containing aggregated statistics:
      - events_count: Number of upcoming events in the city
      - venues_count: Number of venues in the city
      - categories_count: Number of event categories available

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> city = Repo.get(City, 1) |> Repo.preload(:country)
      iex> stats = %{events_count: 127, venues_count: 45, categories_count: 12}
      iex> EventasaurusWeb.JsonLd.CitySchema.generate(city, stats)
      "{\"@context\":\"https://schema.org\",\"@type\":\"City\",...}"
  """
  def generate(city, stats \\ %{}) do
    city
    |> build_city_schema(stats)
    |> Jason.encode!()
  end

  @doc """
  Builds the city schema map (without JSON encoding).
  Useful for testing or combining with other schemas.
  """
  def build_city_schema(city, stats \\ %{}) do
    base_url = UrlHelper.get_base_url()

    # Add stats to city map for hash generation
    city_with_stats = Map.put(city, :stats, stats)

    %{
      "@context" => "https://schema.org",
      "@type" => "City",
      "name" => city.name,
      "url" => "#{base_url}/c/#{city.slug}",
      "description" => build_description(city, stats)
    }
    |> add_geo_coordinates(city)
    |> add_contained_in_place(city)
    |> add_image(city_with_stats, base_url)
    |> add_same_as(city)
    |> add_additional_properties(stats)
  end

  # Build a compelling description for the city
  defp build_description(city, stats) do
    events_count = Map.get(stats, :events_count, 0)
    country_name = if city.country, do: city.country.name, else: ""

    cond do
      events_count > 0 and country_name != "" ->
        "Discover #{events_count} upcoming events in #{city.name}, #{country_name}. Find concerts, festivals, nightlife, cultural events and more happening in the city."

      events_count > 0 ->
        "Discover #{events_count} upcoming events in #{city.name}. Find concerts, festivals, nightlife, cultural events and more happening in the city."

      country_name != "" ->
        "Discover upcoming events in #{city.name}, #{country_name}. Find concerts, festivals, nightlife, cultural events and more happening in the city."

      true ->
        "Discover upcoming events in #{city.name}. Find concerts, festivals, nightlife, cultural events and more happening in the city."
    end
  end

  # Add geo coordinates if available
  defp add_geo_coordinates(schema, city) do
    if city.latitude && city.longitude do
      # Convert Decimal to float for JSON compatibility
      lat = Decimal.to_float(city.latitude)
      lng = Decimal.to_float(city.longitude)

      Map.put(schema, "geo", %{
        "@type" => "GeoCoordinates",
        "latitude" => lat,
        "longitude" => lng
      })
    else
      schema
    end
  end

  # Add country information
  defp add_contained_in_place(schema, city) do
    if city.country do
      Map.put(schema, "containedInPlace", %{
        "@type" => "Country",
        "name" => city.country.name
      })
    else
      schema
    end
  end

  # Add image using actual social card URL
  defp add_image(schema, city, base_url) do
    # Generate social card URL with hash
    alias Eventasaurus.SocialCards.HashGenerator

    # Create a city map with stats for hash generation
    city_with_stats =
      if Map.has_key?(city, :stats) do
        city
      else
        # If stats aren't already in the city map, we'll use empty stats
        # The calling code should populate stats before generating JSON-LD
        Map.put(city, :stats, %{events_count: 0, venues_count: 0, categories_count: 0})
      end

    # Generate the hash-based social card URL
    relative_path = HashGenerator.generate_url_path(city_with_stats, :city)
    image_url = "#{base_url}#{relative_path}"

    # Wrap with CDN for Cloudflare pass-through
    cdn_image_url = CDN.url(image_url)

    Map.put(schema, "image", cdn_image_url)
  end

  # Add sameAs links to external resources
  defp add_same_as(schema, city) do
    same_as_links = []

    # Add Wikipedia link (could be enhanced with actual Wikipedia lookup)
    # For now, just add the search URL which is better than nothing
    same_as_links =
      same_as_links ++
        [
          "https://en.wikipedia.org/wiki/#{URI.encode(city.name)}"
        ]

    # Only add if we have links
    if Enum.any?(same_as_links) do
      Map.put(schema, "sameAs", same_as_links)
    else
      schema
    end
  end

  # Add additional structured data properties using AdditionalProperty
  # This is a flexible way to include custom stats without breaking schema.org compliance
  defp add_additional_properties(schema, stats) do
    events_count = Map.get(stats, :events_count, 0)
    venues_count = Map.get(stats, :venues_count, 0)
    categories_count = Map.get(stats, :categories_count, 0)

    # Only add if we have meaningful stats
    if events_count > 0 or venues_count > 0 or categories_count > 0 do
      additional_properties = []

      additional_properties =
        if events_count > 0 do
          additional_properties ++
            [
              %{
                "@type" => "PropertyValue",
                "name" => "Upcoming Events",
                "value" => events_count
              }
            ]
        else
          additional_properties
        end

      additional_properties =
        if venues_count > 0 do
          additional_properties ++
            [
              %{
                "@type" => "PropertyValue",
                "name" => "Event Venues",
                "value" => venues_count
              }
            ]
        else
          additional_properties
        end

      additional_properties =
        if categories_count > 0 do
          additional_properties ++
            [
              %{
                "@type" => "PropertyValue",
                "name" => "Event Categories",
                "value" => categories_count
              }
            ]
        else
          additional_properties
        end

      if Enum.any?(additional_properties) do
        Map.put(schema, "additionalProperty", additional_properties)
      else
        schema
      end
    else
      schema
    end
  end
end
