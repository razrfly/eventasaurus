defmodule EventasaurusDiscovery.Sources.KinoKrakow.Transformer do
  @moduledoc """
  Transforms Kino Krakow showtime data into unified format for the Processor.

  IMPORTANT: All events MUST have:
  - Movie data (title, TMDB ID)
  - Venue with complete location data (cinema)
  - Valid start time
  """

  require Logger

  @doc """
  Transform raw Kino Krakow showtime into unified event format.

  Input should include:
  - showtime data (from ShowtimeExtractor)
  - movie data (from MovieExtractor + TmdbMatcher)
  - cinema data (from CinemaExtractor)

  Returns {:ok, transformed_event} or {:error, reason}
  """
  def transform_event(raw_event) do
    case validate_required_fields(raw_event) do
      :ok ->
        transformed = %{
          # Required fields
          title: build_title(raw_event),
          external_id: build_external_id(raw_event),
          starts_at: raw_event.datetime,
          ends_at: calculate_end_time(raw_event),

          # Venue data - REQUIRED
          venue_data: build_venue_data(raw_event),

          # Movie data - link to movies table
          movie_id: raw_event.movie_id,
          movie_data: %{
            tmdb_id: raw_event.tmdb_id,
            title: raw_event.movie_title,
            original_title: raw_event.original_title
          },

          # Optional fields
          description: raw_event[:description],
          ticket_url: raw_event.ticket_url,

          # Movie images from TMDB
          image_url: raw_event[:poster_url] || raw_event[:backdrop_url],

          # Pricing (usually not available from scraping)
          is_free: false,
          min_price: nil,
          max_price: nil,
          currency: "PLN",

          # Category - always movies
          category: "movies",

          # Metadata
          metadata: %{
            source: "kino-krakow",
            cinema_slug: raw_event.cinema_slug,
            movie_slug: raw_event.movie_slug,
            confidence_score: raw_event[:tmdb_confidence],
            # Store movie page URL for source link
            movie_url: build_movie_url(raw_event.movie_slug)
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
    cond do
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

  # Build unique external ID
  defp build_external_id(event) do
    # Combine movie slug, cinema slug, and datetime for uniqueness
    datetime_str = DateTime.to_iso8601(event.datetime)
    "#{event.movie_slug}-#{event.cinema_slug}-#{datetime_str}"
  end

  # Calculate end time based on movie runtime
  defp calculate_end_time(event) do
    runtime = event[:runtime] || 120  # Default 2 hours if unknown

    DateTime.add(event.datetime, runtime * 60, :second)
  end

  # Build venue data for processor
  # VenueProcessor will geocode automatically if latitude/longitude are nil
  defp build_venue_data(event) do
    cinema = event.cinema_data

    %{
      name: cinema.name,
      address: cinema[:address],
      city: cinema[:city] || "Kraków",
      country: cinema[:country] || "Poland",
      latitude: cinema[:latitude],
      longitude: cinema[:longitude],
      phone: cinema[:phone],
      metadata: %{
        cinema_slug: event.cinema_slug,
        hours: cinema[:hours]
      }
    }
  end

  # Build movie detail page URL
  defp build_movie_url(movie_slug) do
    EventasaurusDiscovery.Sources.KinoKrakow.Config.movie_detail_url(movie_slug)
  end
end
