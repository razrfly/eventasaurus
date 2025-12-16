defmodule EventasaurusWeb.JsonLd.Helpers do
  @moduledoc """
  Shared utilities for JSON-LD schema generation.

  This module provides common helper functions used across all JSON-LD schema
  modules to reduce code duplication and ensure consistency.

  ## Functions

  ### Field Manipulation
  - `maybe_add/3` - Conditionally add a field if value is not nil or empty
  - `maybe_add_if_missing/3` - Add a field only if it doesn't already exist

  ### URL Building
  - `get_base_url/0` - Get the application base URL
  - `build_url/1` - Build a full URL from a path

  ### Geo Coordinates
  - `add_geo_coordinates/2` - Add GeoCoordinates schema to an entity

  ### Text Helpers
  - `pluralize/2` - Simple pluralization for common words

  ### Image Handling
  - `cdn_url/1` - Wrap an image URL with CDN

  ### Duration Formatting
  - `format_iso_duration/1` - Format minutes as ISO 8601 duration
  """

  alias Eventasaurus.CDN

  # ============================================================================
  # Field Manipulation
  # ============================================================================

  @doc """
  Conditionally add a field to a schema map if the value is not nil or empty.

  ## Examples

      iex> Helpers.maybe_add(%{}, "name", "Test")
      %{"name" => "Test"}

      iex> Helpers.maybe_add(%{}, "name", nil)
      %{}

      iex> Helpers.maybe_add(%{}, "tags", [])
      %{}
  """
  @spec maybe_add(map(), String.t(), any()) :: map()
  def maybe_add(schema, _key, nil), do: schema
  def maybe_add(schema, _key, []), do: schema
  def maybe_add(schema, _key, ""), do: schema
  def maybe_add(schema, key, value), do: Map.put(schema, key, value)

  @doc """
  Conditionally add a field to a schema map only if the key doesn't already exist.

  Useful for fallback values where you don't want to overwrite existing data.

  ## Examples

      iex> Helpers.maybe_add_if_missing(%{}, "name", "Fallback")
      %{"name" => "Fallback"}

      iex> Helpers.maybe_add_if_missing(%{"name" => "Primary"}, "name", "Fallback")
      %{"name" => "Primary"}

      iex> Helpers.maybe_add_if_missing(%{}, "name", nil)
      %{}
  """
  @spec maybe_add_if_missing(map(), String.t(), any()) :: map()
  def maybe_add_if_missing(schema, _key, nil), do: schema
  def maybe_add_if_missing(schema, _key, []), do: schema
  def maybe_add_if_missing(schema, _key, ""), do: schema
  def maybe_add_if_missing(schema, _key, "N/A"), do: schema

  def maybe_add_if_missing(schema, key, value) do
    if Map.has_key?(schema, key) do
      schema
    else
      Map.put(schema, key, value)
    end
  end

  # ============================================================================
  # URL Building
  # ============================================================================

  @doc """
  Get the application base URL from configuration.

  Falls back to "https://eventasaurus.co" if not configured.

  ## Examples

      iex> Helpers.get_base_url()
      "https://eventasaurus.co"
  """
  @spec get_base_url() :: String.t()
  def get_base_url do
    EventasaurusWeb.Layouts.get_base_url()
  end

  @doc """
  Build a full URL by combining the base URL with a path.

  ## Examples

      iex> Helpers.build_url("/movies/inception-12345")
      "https://eventasaurus.co/movies/inception-12345"

      iex> Helpers.build_url("/c/krakow/events")
      "https://eventasaurus.co/c/krakow/events"
  """
  @spec build_url(String.t()) :: String.t()
  def build_url(path) do
    "#{get_base_url()}#{path}"
  end

  # ============================================================================
  # Geo Coordinates
  # ============================================================================

  @doc """
  Add GeoCoordinates schema to an entity if latitude and longitude are available.

  The entity must have `latitude` and `longitude` fields (can be accessed via
  map or struct).

  ## Examples

      iex> Helpers.add_geo_coordinates(%{"name" => "Place"}, %{latitude: 50.06, longitude: 19.94})
      %{"name" => "Place", "geo" => %{"@type" => "GeoCoordinates", "latitude" => 50.06, "longitude" => 19.94}}

      iex> Helpers.add_geo_coordinates(%{"name" => "Place"}, %{latitude: nil, longitude: nil})
      %{"name" => "Place"}
  """
  @spec add_geo_coordinates(map(), map() | struct()) :: map()
  def add_geo_coordinates(schema, entity) do
    lat = get_field(entity, :latitude)
    lng = get_field(entity, :longitude)

    if lat && lng do
      Map.put(schema, "geo", %{
        "@type" => "GeoCoordinates",
        "latitude" => maybe_convert_decimal(lat),
        "longitude" => maybe_convert_decimal(lng)
      })
    else
      schema
    end
  end

  # Convert Decimal to float if necessary (for JSON compatibility)
  defp maybe_convert_decimal(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp maybe_convert_decimal(value), do: value

  # Helper to get a field from either a map or struct
  defp get_field(nil, _key), do: nil

  defp get_field(entity, key) when is_map(entity) do
    Map.get(entity, key) || Map.get(entity, to_string(key))
  end

  # ============================================================================
  # Text Helpers
  # ============================================================================

  @doc """
  Simple pluralization for common words.

  Handles special cases like "city" -> "cities" and defaults to adding "s".

  ## Examples

      iex> Helpers.pluralize("movie", 1)
      "movie"

      iex> Helpers.pluralize("movie", 5)
      "movies"

      iex> Helpers.pluralize("city", 3)
      "cities"

      iex> Helpers.pluralize("cinema", 2)
      "cinemas"
  """
  @spec pluralize(String.t(), integer()) :: String.t()
  def pluralize(word, 1), do: word
  def pluralize("city", _), do: "cities"
  def pluralize("category", _), do: "categories"
  def pluralize(word, _), do: word <> "s"

  # ============================================================================
  # Image Handling
  # ============================================================================

  @doc """
  Wrap an image URL with the CDN for caching and optimization.

  Returns nil if the input URL is nil or empty.

  ## Examples

      iex> Helpers.cdn_url("https://image.tmdb.org/t/p/w500/poster.jpg")
      "https://cdn.eventasaurus.co/image?url=https%3A%2F%2Fimage.tmdb.org..."

      iex> Helpers.cdn_url(nil)
      nil

      iex> Helpers.cdn_url("")
      nil
  """
  @spec cdn_url(String.t() | nil) :: String.t() | nil
  def cdn_url(nil), do: nil
  def cdn_url(""), do: nil
  def cdn_url(url), do: CDN.url(url)

  # ============================================================================
  # Duration Formatting
  # ============================================================================

  @doc """
  Format runtime in minutes as ISO 8601 duration format.

  Used for movie durations and event lengths.

  ## Examples

      iex> Helpers.format_iso_duration(142)
      "PT2H22M"

      iex> Helpers.format_iso_duration(60)
      "PT1H"

      iex> Helpers.format_iso_duration(45)
      "PT45M"

      iex> Helpers.format_iso_duration(nil)
      nil

      iex> Helpers.format_iso_duration(0)
      nil
  """
  @spec format_iso_duration(integer() | nil) :: String.t() | nil
  def format_iso_duration(nil), do: nil
  def format_iso_duration(0), do: nil

  def format_iso_duration(runtime) when is_integer(runtime) and runtime > 0 do
    hours = div(runtime, 60)
    minutes = rem(runtime, 60)

    cond do
      hours > 0 and minutes > 0 -> "PT#{hours}H#{minutes}M"
      hours > 0 -> "PT#{hours}H"
      minutes > 0 -> "PT#{minutes}M"
      true -> nil
    end
  end

  def format_iso_duration(_), do: nil

  # ============================================================================
  # TMDB Metadata Extraction
  # ============================================================================

  @doc """
  Extract genre names from TMDb genres array.

  ## Examples

      iex> Helpers.extract_genres([%{"name" => "Action"}, %{"name" => "Drama"}])
      ["Action", "Drama"]

      iex> Helpers.extract_genres(nil)
      nil

      iex> Helpers.extract_genres([])
      nil
  """
  @spec extract_genres(list() | nil) :: list() | nil
  def extract_genres(nil), do: nil
  def extract_genres([]), do: nil

  def extract_genres(genres) when is_list(genres) do
    Enum.map(genres, fn genre -> genre["name"] end)
  end

  @doc """
  Extract directors from TMDb credits as Person schemas.

  Returns a single Person map for one director, or a list for multiple.

  ## Examples

      iex> credits = %{"crew" => [%{"job" => "Director", "name" => "Christopher Nolan"}]}
      iex> Helpers.extract_directors(credits)
      %{"@type" => "Person", "name" => "Christopher Nolan"}
  """
  @spec extract_directors(map() | nil) :: map() | list() | nil
  def extract_directors(nil), do: nil

  def extract_directors(credits) do
    case get_in(credits, ["crew"]) do
      nil ->
        nil

      crew ->
        directors =
          crew
          |> Enum.filter(fn person -> person["job"] == "Director" end)
          |> Enum.map(fn person ->
            %{
              "@type" => "Person",
              "name" => person["name"]
            }
          end)

        case directors do
          [] -> nil
          [single] -> single
          multiple -> multiple
        end
    end
  end

  @doc """
  Extract actors from TMDb credits as Person schemas.

  Takes the top 10 cast members by default.

  ## Examples

      iex> credits = %{"cast" => [%{"name" => "Leonardo DiCaprio"}]}
      iex> Helpers.extract_actors(credits)
      [%{"@type" => "Person", "name" => "Leonardo DiCaprio"}]
  """
  @spec extract_actors(map() | nil, integer()) :: list() | nil
  def extract_actors(credits, limit \\ 10)
  def extract_actors(nil, _limit), do: nil

  def extract_actors(credits, limit) do
    case get_in(credits, ["cast"]) do
      nil ->
        nil

      cast ->
        actors =
          cast
          |> Enum.take(limit)
          |> Enum.map(fn person ->
            %{
              "@type" => "Person",
              "name" => person["name"]
            }
          end)

        case actors do
          [] -> nil
          list -> list
        end
    end
  end

  @doc """
  Build TMDb aggregate rating schema.

  Returns nil if vote_average or vote_count is missing or zero.

  ## Examples

      iex> Helpers.build_aggregate_rating(%{"vote_average" => 8.2, "vote_count" => 5000})
      %{"@type" => "AggregateRating", "ratingValue" => 8.2, "ratingCount" => 5000, "bestRating" => 10, "worstRating" => 0}
  """
  @spec build_aggregate_rating(map() | nil) :: map() | nil
  def build_aggregate_rating(nil), do: nil

  def build_aggregate_rating(metadata) do
    vote_average = metadata["vote_average"]
    vote_count = metadata["vote_count"]

    if vote_average && vote_count && vote_count > 0 do
      %{
        "@type" => "AggregateRating",
        "ratingValue" => vote_average,
        "ratingCount" => vote_count,
        "bestRating" => 10,
        "worstRating" => 0
      }
    else
      nil
    end
  end

  # ============================================================================
  # Address Building
  # ============================================================================

  @doc """
  Build a PostalAddress schema from venue and city data.

  ## Examples

      iex> venue = %{address: "123 Main St"}
      iex> city = %{name: "Krakow", country: %{code: "PL"}}
      iex> Helpers.build_postal_address(venue, city)
      %{"@type" => "PostalAddress", "streetAddress" => "123 Main St", "addressLocality" => "Krakow", "addressCountry" => "PL"}
  """
  @spec build_postal_address(map() | struct(), map() | struct()) :: map()
  def build_postal_address(venue, city) do
    country_code =
      get_nested_field(city, [:country, :code]) ||
        get_field(city, :country_code) ||
        "US"

    %{
      "@type" => "PostalAddress",
      "streetAddress" => get_field(venue, :address) || "",
      "addressLocality" => get_field(city, :name),
      "addressCountry" => country_code
    }
  end

  # Helper to get nested field from map or struct
  defp get_nested_field(nil, _keys), do: nil

  defp get_nested_field(entity, keys) when is_map(entity) do
    Enum.reduce_while(keys, entity, fn key, acc ->
      case acc do
        nil -> {:halt, nil}
        map when is_map(map) -> {:cont, Map.get(map, key) || Map.get(map, to_string(key))}
        _ -> {:halt, nil}
      end
    end)
  end
end
