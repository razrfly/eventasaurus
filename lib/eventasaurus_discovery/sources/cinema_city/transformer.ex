defmodule EventasaurusDiscovery.Sources.CinemaCity.Transformer do
  @moduledoc """
  Transforms Cinema City showtime data into unified format for the Processor.

  IMPORTANT: All events MUST have:
  - Movie data (title, TMDB ID)
  - Venue with complete location data (cinema)
  - Valid start time

  Adapted from Kino Krakow transformer but using Cinema City's API data structure.
  """

  require Logger

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
        # Helper to get value from map with both atom and string keys
        get_value = fn map, key ->
          map[key] || map[to_string(key)]
        end

        cinema_data = get_value.(raw_event, :cinema_data)

        transformed = %{
          # Required fields
          title: build_title(raw_event),
          external_id: get_value.(raw_event, :external_id),
          starts_at: get_value.(raw_event, :showtime),
          ends_at: calculate_end_time(raw_event),

          # Venue data - REQUIRED
          venue_data: build_venue_data(raw_event),

          # Movie data - link to movies table
          movie_id: get_value.(raw_event, :movie_id),
          movie_data: %{
            tmdb_id: get_value.(raw_event, :tmdb_id),
            title: get_value.(raw_event, :movie_title),
            original_title: get_value.(raw_event, :original_title)
          },

          # Optional fields
          description: build_description(raw_event),
          ticket_url: get_value.(raw_event, :booking_url),

          # Movie images from TMDB
          image_url: get_value.(raw_event, :poster_url) || get_value.(raw_event, :backdrop_url),

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
            cinema_city_id: cinema_data["cinema_city_id"],
            cinema_city_event_id: get_value.(raw_event, :cinema_city_event_id),
            auditorium: get_value.(raw_event, :auditorium),
            language_info: get_value.(raw_event, :language_info),
            format_info: get_value.(raw_event, :format_info),
            genre_tags: get_value.(raw_event, :genre_tags),
            cinema_website: cinema_data["website"]
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
      is_nil(event[:showtime]) ->
        {:error, "Missing showtime"}

      is_nil(event[:movie_id]) ->
        {:error, "Missing movie_id"}

      is_nil(event[:cinema_data]) ->
        {:error, "Missing cinema data"}

      is_nil(event.cinema_data["name"]) ->
        {:error, "Missing cinema name"}

      true ->
        :ok
    end
  end

  # Build event title: "Movie Title at Cinema Name"
  defp build_title(event) do
    movie_title = event[:movie_title] || event[:original_title] || "Unknown Movie"
    cinema_name = event.cinema_data["name"] || "Unknown Cinema"

    "#{movie_title} at #{cinema_name}"
  end

  # Build description with language and format info
  defp build_description(event) do
    parts = []

    # Add language info
    language_info = event[:language_info] || %{}

    language_parts =
      cond do
        language_info[:is_dubbed] -> ["Dubbed (#{language_info[:dubbed_language]})"]
        language_info[:is_subbed] -> ["Subtitled"]
        true -> []
      end

    parts = parts ++ language_parts

    # Add format info
    format_info = event[:format_info] || %{}

    format_parts =
      []
      |> maybe_add(format_info[:is_3d], "3D")
      |> maybe_add(format_info[:is_imax], "IMAX")
      |> maybe_add(format_info[:is_4dx], "4DX")
      |> maybe_add(format_info[:is_vip], "VIP")

    parts = parts ++ format_parts

    # Add auditorium
    parts =
      if event[:auditorium] do
        parts ++ ["Auditorium: #{event[:auditorium]}"]
      else
        parts
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
    runtime = event[:runtime] || 120
    showtime = event[:showtime]

    DateTime.add(showtime, runtime * 60, :second)
  end

  # Build venue data for processor
  # VenueProcessor will geocode automatically if latitude/longitude are nil
  defp build_venue_data(event) do
    cinema = event[:cinema_data]

    %{
      name: cinema["name"],
      address: cinema["address"],
      city: cinema["city"],
      country: cinema["country"] || "Poland",
      latitude: cinema["latitude"],
      longitude: cinema["longitude"],
      phone: nil,
      # Not provided by Cinema City API
      metadata: %{
        cinema_city_id: cinema["cinema_city_id"],
        website: cinema["website"]
      }
    }
  end
end
