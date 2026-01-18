defmodule EventasaurusDiscovery.Sources.Repertuary.Transformer do
  @moduledoc """
  Transforms Repertuary.pl showtime data into unified format for the Processor.

  ## Multi-City Support

  Pass the city key to get city-specific transformations:

      Transformer.transform_event(raw_event, "warszawa")

  Defaults to "krakow" for backward compatibility.

  IMPORTANT: All events MUST have:
  - Movie data (title, TMDB ID)
  - Venue with complete location data (cinema)
  - Valid start time
  """

  require Logger

  alias EventasaurusDiscovery.Sources.Repertuary.{Config, Cities}
  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

  @doc """
  Transform raw Repertuary.pl showtime into unified event format.

  Input should include:
  - showtime data (from ShowtimeExtractor)
  - movie data (from MovieExtractor + TmdbMatcher)
  - cinema data (from CinemaExtractor)

  ## Parameters
  - raw_event: Map containing showtime, movie, and cinema data
  - city: City key (e.g., "krakow", "warszawa"). Defaults to "krakow".

  Returns {:ok, transformed_event} or {:error, reason}
  """
  def transform_event(raw_event, city \\ Config.default_city()) do
    city_config = Cities.get(city) || Cities.get(Config.default_city())

    case validate_required_fields(raw_event) do
      :ok ->
        # Helper to get value from map with both atom and string keys
        get_value = fn map, key ->
          map[key] || map[to_string(key)]
        end

        movie_slug = get_value.(raw_event, :movie_slug)
        cinema_slug = get_value.(raw_event, :cinema_slug)

        transformed = %{
          # Required fields
          title: build_title(raw_event),
          external_id: get_value.(raw_event, :external_id),
          starts_at: get_value.(raw_event, :datetime),
          ends_at: calculate_end_time(raw_event),

          # Venue data - REQUIRED (city-aware)
          venue_data: build_venue_data(raw_event, city_config),

          # Movie data - link to movies table
          movie_id: get_value.(raw_event, :movie_id),
          movie_data: %{
            tmdb_id: get_value.(raw_event, :tmdb_id),
            title: get_value.(raw_event, :movie_title),
            original_title: get_value.(raw_event, :original_title)
          },

          # Optional fields
          description: get_value.(raw_event, :description),
          ticket_url: get_value.(raw_event, :ticket_url),

          # Movie images from TMDB
          image_url: get_value.(raw_event, :poster_url) || get_value.(raw_event, :backdrop_url),

          # Pricing (usually not available from scraping)
          is_free: false,
          min_price: nil,
          max_price: nil,
          currency: "PLN",

          # Category - always movies
          category: "movies",

          # Metadata - single source identifier (Cinema City pattern)
          # All cities share the "repertuary" source, city is tracked separately
          metadata: %{
            source: "repertuary",
            city: city,
            cinema_slug: cinema_slug,
            movie_slug: movie_slug,
            confidence_score: get_value.(raw_event, :tmdb_confidence),
            # Store movie page URL for source link (city-specific)
            movie_url: build_movie_url(movie_slug, city),
            # Raw upstream data for debugging (sanitized for JSON)
            _raw_upstream: JsonSanitizer.sanitize(raw_event)
          }
        }

        {:ok, transformed}

      {:error, reason} ->
        Logger.warning("Skipping invalid event (#{city_config.name}): #{reason}")
        {:error, reason}
    end
  end

  # Validate all required fields are present
  # Note: GPS coordinates are NOT required here - VenueProcessor handles geocoding automatically
  defp validate_required_fields(event) do
    cond do
      is_nil(event[:external_id]) and is_nil(event["external_id"]) ->
        {:error, "Missing external_id"}

      is_nil(event[:datetime]) ->
        {:error, "Missing datetime"}

      is_nil(event[:movie_id]) ->
        {:error, "Missing movie_id"}

      is_nil(event[:cinema_data]) ->
        {:error, "Missing cinema data"}

      is_nil(event.cinema_data[:name]) ->
        {:error, "Missing cinema name"}

      true ->
        :ok
    end
  end

  # Build event title: "Movie Title at Cinema Name"
  defp build_title(event) do
    movie_title = event[:movie_title] || event[:original_title] || "Unknown Movie"
    cinema_name = event.cinema_data[:name] || "Unknown Cinema"

    "#{movie_title} at #{cinema_name}"
  end

  # Calculate end time based on movie runtime
  defp calculate_end_time(event) do
    # Default 2 hours if unknown
    runtime = event[:runtime] || event["runtime"] || 120
    datetime = event[:datetime] || event["datetime"]

    DateTime.add(datetime, runtime * 60, :second)
  end

  # Build venue data for processor
  # VenueProcessor will geocode automatically if latitude/longitude are nil
  defp build_venue_data(event, city_config) do
    cinema = event[:cinema_data] || event["cinema_data"]

    %{
      name: cinema[:name] || cinema["name"],
      address: cinema[:address] || cinema["address"],
      # Use city from cinema_data (set by CinemaExtractor) or fall back to city_config
      city: cinema[:city] || cinema["city"] || city_config.name,
      country: cinema[:country] || cinema["country"] || city_config.country,
      latitude: cinema[:latitude] || cinema["latitude"],
      longitude: cinema[:longitude] || cinema["longitude"],
      phone: cinema[:phone] || cinema["phone"],
      metadata: %{
        cinema_slug: event[:cinema_slug] || event["cinema_slug"],
        hours: cinema[:hours] || cinema["hours"]
      }
    }
  end

  # Build movie detail page URL (city-specific)
  defp build_movie_url(movie_slug, city) do
    Config.movie_detail_url(movie_slug, city)
  end
end
