defmodule EventasaurusDiscovery.Sources.CinemaCity.Transformer do
  @moduledoc """
  Transforms Cinema City showtime data into unified format for the Processor.

  IMPORTANT: All events MUST have:
  - Movie data (title, TMDB ID)
  - Venue with complete location data (cinema)
  - Valid start time

  Adapted from Repertuary transformer but using Cinema City's API data structure.

  Handles both atom and string keys throughout (Oban serializes to JSON with string keys).
  """

  require Logger
  alias EventasaurusDiscovery.Helpers.CityResolver
  alias EventasaurusDiscovery.Geocoding.MetadataBuilder

  @doc """
  Transform raw Cinema City showtime into unified event format.

  Input should include:
  - showtime data (from ShowtimeProcessJob)
  - movie data (from MovieDetailJob + TmdbMatcher)
  - cinema data (from CinemaExtractor)

  Returns {:ok, transformed_event} or {:error, reason}
  """
  def transform_event(raw_event) do
    case validate_required_fields(raw_event) do
      :ok ->
        cinema_data = fetch(raw_event, :cinema_data) || %{}

        transformed = %{
          # Required fields
          title: build_title(raw_event),
          external_id: fetch(raw_event, :external_id),
          starts_at: fetch(raw_event, :showtime),
          ends_at: calculate_end_time(raw_event),

          # Venue data - REQUIRED
          venue_data: build_venue_data(raw_event),

          # Movie data - link to movies table
          movie_id: fetch(raw_event, :movie_id),
          movie_data: %{
            tmdb_id: fetch(raw_event, :tmdb_id),
            title: fetch(raw_event, :movie_title),
            original_title: fetch(raw_event, :original_title)
          },

          # Optional fields
          description: build_description(raw_event),

          # Source URL - use cinema website for general movie listings
          # This shows all showtimes for the cinema, not a specific booking
          source_url: fetch(cinema_data, :website),

          # Movie images from TMDB
          image_url: fetch(raw_event, :poster_url) || fetch(raw_event, :backdrop_url),

          # Pricing (usually not available from scraping)
          is_free: false,
          min_price: nil,
          max_price: nil,
          currency: "PLN",

          # Category - always movies
          category: "movies",

          # Metadata
          metadata: %{
            source: "cinema-city",
            cinema_city_id: fetch(cinema_data, :cinema_city_id),
            cinema_city_event_id: fetch(raw_event, :cinema_city_event_id),
            auditorium: fetch(raw_event, :auditorium),
            language_info: fetch(raw_event, :language_info),
            format_info: fetch(raw_event, :format_info),
            genre_tags: fetch(raw_event, :genre_tags),
            cinema_website: fetch(cinema_data, :website),
            # Raw upstream data for debugging
            _raw_upstream: raw_event
          }
        }

        {:ok, transformed}

      {:error, reason} ->
        Logger.warning("Skipping invalid event: #{reason}")
        {:error, reason}
    end
  end

  # Validate all required fields are present
  # Note: GPS coordinates are NOT required here - VenueProcessor handles geocoding automatically
  defp validate_required_fields(event) do
    cinema = fetch(event, :cinema_data)

    cond do
      is_nil(fetch(event, :showtime)) ->
        {:error, "Missing showtime"}

      is_nil(fetch(event, :movie_id)) ->
        {:error, "Missing movie_id"}

      is_nil(cinema) ->
        {:error, "Missing cinema data"}

      is_nil(fetch(cinema, :name)) ->
        {:error, "Missing cinema name"}

      true ->
        :ok
    end
  end

  # Build event title: "Movie Title at Cinema Name"
  defp build_title(event) do
    movie_title =
      fetch(event, :movie_title) ||
        fetch(event, :original_title) ||
        "Unknown Movie"

    cinema = fetch(event, :cinema_data) || %{}
    cinema_name = fetch(cinema, :name) || "Unknown Cinema"

    "#{movie_title} at #{cinema_name}"
  end

  # Build description with language and format info
  defp build_description(event) do
    parts = []

    # Add language info
    language_info = fetch(event, :language_info) || %{}

    language_parts =
      cond do
        fetch(language_info, :is_dubbed) ->
          ["Dubbed (#{fetch(language_info, :dubbed_language)})"]

        fetch(language_info, :is_subbed) ->
          ["Subtitled"]

        true ->
          []
      end

    parts = parts ++ language_parts

    # Add format info
    format_info = fetch(event, :format_info) || %{}

    format_parts =
      []
      |> maybe_add(fetch(format_info, :is_3d), "3D")
      |> maybe_add(fetch(format_info, :is_imax), "IMAX")
      |> maybe_add(fetch(format_info, :is_4dx), "4DX")
      |> maybe_add(fetch(format_info, :is_vip), "VIP")

    parts = parts ++ format_parts

    # Add auditorium
    parts =
      case fetch(event, :auditorium) do
        nil -> parts
        auditorium -> parts ++ ["Auditorium: #{auditorium}"]
      end

    # Join parts
    case parts do
      [] -> nil
      _ -> Enum.join(parts, " • ")
    end
  end

  # Helper to conditionally add to list
  defp maybe_add(list, true, value), do: list ++ [value]
  defp maybe_add(list, _, _), do: list

  # Calculate end time based on movie runtime
  defp calculate_end_time(event) do
    # Default 2 hours if unknown
    runtime = fetch(event, :runtime) || 120
    showtime = fetch(event, :showtime)

    DateTime.add(showtime, runtime * 60, :second)
  end

  # Build venue data for processor
  # VenueProcessor will geocode automatically if latitude/longitude are nil
  defp build_venue_data(event) do
    cinema = fetch(event, :cinema_data) || %{}

    latitude = fetch(cinema, :latitude)
    longitude = fetch(cinema, :longitude)
    api_city = fetch(cinema, :city)

    # Resolve city using CityResolver with coordinates if available
    {resolved_city, resolved_country} = resolve_location(latitude, longitude, api_city, "Poland")

    # Build CityResolver metadata (offline reverse geocoding - free)
    geocoding_metadata =
      MetadataBuilder.build_city_resolver_metadata()
      |> MetadataBuilder.add_scraper_source("cinema_city")

    %{
      name: fetch(cinema, :name),
      address: fetch(cinema, :address),
      city: resolved_city,
      country: resolved_country,
      latitude: latitude,
      longitude: longitude,
      phone: nil,
      # Not provided by Cinema City API
      geocoding_metadata: geocoding_metadata,
      metadata: %{
        cinema_city_id: fetch(cinema, :cinema_city_id),
        website: fetch(cinema, :website)
      }
    }
  end

  @doc """
  Resolves city and country from GPS coordinates using offline geocoding.

  Uses CityResolver for reliable city name extraction from coordinates.
  Falls back to conservative validation of API-provided city name if geocoding fails.

  ## Parameters
  - `latitude` - GPS latitude coordinate (may be nil)
  - `longitude` - GPS longitude coordinate (may be nil)
  - `api_city` - City name from Cinema City API (fallback only)
  - `known_country` - Country from context (Poland)

  ## Returns
  - `{city_name, country}` tuple
  """
  def resolve_location(latitude, longitude, api_city, known_country) do
    case CityResolver.resolve_city(latitude, longitude) do
      {:ok, city_name} ->
        # Successfully resolved city from coordinates
        {city_name, known_country}

      {:error, reason} ->
        # Geocoding failed - log and fall back to conservative validation
        Logger.warning(
          "Geocoding failed for (#{inspect(latitude)}, #{inspect(longitude)}): #{reason}. Falling back to API city validation."
        )

        validate_api_city(api_city, known_country)
    end
  end

  # Conservative fallback - validates API city name before using
  # Prefers nil over garbage data
  defp validate_api_city(api_city, known_country) when is_binary(api_city) do
    city_trimmed = String.trim(api_city)

    # CRITICAL: Validate city candidate before using
    case CityResolver.validate_city_name(city_trimmed) do
      {:ok, validated_city} ->
        {validated_city, known_country}

      {:error, reason} ->
        # City candidate failed validation (postcode, street address, etc.)
        Logger.warning(
          "Cinema City API returned invalid city: #{inspect(city_trimmed)} (#{reason})"
        )

        {nil, known_country}
    end
  end

  defp validate_api_city(_api_city, known_country) do
    {nil, known_country}
  end

  # Helper to get value from map with both atom and string keys
  # Handles Oban's JSON serialization which converts atoms to strings
  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp fetch(_, _), do: nil
end
