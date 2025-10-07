defmodule EventasaurusDiscovery.Sources.CinemaCity.Extractors.EventExtractor do
  @moduledoc """
  Extracts film and showtime data from Cinema City API responses.

  The API provides structured JSON data for:
  - Films: Movie metadata (title, year, runtime, poster, etc.)
  - Events: Showtime information (time, auditorium, booking link, etc.)

  This extractor normalizes the API data into a format suitable for:
  1. TMDB matching (to get rich metadata)
  2. Creating Movie records
  3. Creating Showtime records
  """

  require Logger

  @doc """
  Extract film metadata from API response.

  ## Input Example
  ```json
  {
    "id": "7592s3r",
    "name": "Avatar: Istota wody",
    "length": 192,
    "releaseYear": "2022",
    "posterLink": "https://...",
    "videoLink": "https://...",
    "attributeIds": ["3d", "dubbed-lang-pl", "sci-fi"]
  }
  ```

  ## Returns
  Map with:
  - cinema_city_film_id: String
  - polish_title: String
  - runtime: Integer (minutes)
  - release_year: Integer
  - poster_url: String
  - trailer_url: String
  - attributes: List of strings (format, language, genre tags)
  - language_info: Map (detected from attributes)
  - format_info: Map (2D/3D, IMAX, etc.)
  """
  def extract_film(film_data) when is_map(film_data) do
    attributes = extract_attributes(film_data)

    %{
      cinema_city_film_id: extract_film_id(film_data),
      polish_title: extract_title(film_data),
      runtime: extract_runtime(film_data),
      release_year: extract_year(film_data),
      poster_url: extract_poster(film_data),
      trailer_url: extract_trailer(film_data),
      attributes: attributes,
      language_info: parse_language_attributes(attributes),
      format_info: parse_format_attributes(attributes),
      genre_tags: parse_genre_attributes(attributes)
    }
  end

  @doc """
  Extract showtime/event metadata from API response.

  ## Input Example
  ```json
  {
    "id": "123456",
    "filmId": "7592s3r",
    "cinemaId": "1088",
    "businessDay": "2025-10-03",
    "eventDateTime": "2025-10-03T19:30:00",
    "auditorium": "Sala 5",
    "bookingLink": "https://www.cinema-city.pl/buy/..."
  }
  ```

  ## Returns
  Map with:
  - cinema_city_event_id: String
  - cinema_city_film_id: String (links to film)
  - cinema_city_cinema_id: String (links to cinema)
  - showtime: DateTime
  - business_day: Date
  - auditorium: String
  - booking_url: String
  """
  def extract_event(event_data) when is_map(event_data) do
    %{
      cinema_city_event_id: extract_event_id(event_data),
      cinema_city_film_id: extract_film_id_from_event(event_data),
      cinema_city_cinema_id: extract_cinema_id_from_event(event_data),
      showtime: extract_showtime(event_data),
      business_day: extract_business_day(event_data),
      auditorium: extract_auditorium(event_data),
      booking_url: extract_booking_url(event_data)
    }
  end

  @doc """
  Group events by film ID for easier processing.

  Returns a map of %{film_id => [event1, event2, ...]}
  """
  def group_events_by_film(events) when is_list(events) do
    events
    |> Enum.group_by(fn event ->
      extract_film_id_from_event(event)
    end)
  end

  @doc """
  Match films with their events.

  Returns a list of %{film: film_data, events: [event1, event2, ...]}
  """
  def match_films_with_events(films, events) when is_list(films) and is_list(events) do
    events_by_film = group_events_by_film(events)

    films
    |> Enum.map(fn film ->
      film_id = extract_film_id(film)
      film_events = Map.get(events_by_film, film_id, [])

      %{
        film: extract_film(film),
        events: Enum.map(film_events, &extract_event/1)
      }
    end)
    |> Enum.reject(fn %{events: events} -> Enum.empty?(events) end)
  end

  # Private extraction functions

  defp extract_film_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_film_id(%{"id" => id}) when is_integer(id), do: Integer.to_string(id)
  defp extract_film_id(_), do: nil

  defp extract_title(%{"name" => name}) when is_binary(name), do: String.trim(name)
  defp extract_title(_), do: nil

  defp extract_runtime(%{"length" => length}) when is_integer(length), do: length

  defp extract_runtime(%{"length" => length}) when is_binary(length) do
    case Integer.parse(length) do
      {int_val, _} -> int_val
      :error -> nil
    end
  end

  defp extract_runtime(_), do: nil

  defp extract_year(%{"releaseYear" => year}) when is_integer(year), do: year

  defp extract_year(%{"releaseYear" => year}) when is_binary(year) do
    case Integer.parse(year) do
      {int_val, _} -> int_val
      :error -> nil
    end
  end

  defp extract_year(_), do: nil

  defp extract_poster(%{"posterLink" => url}) when is_binary(url), do: String.trim(url)
  defp extract_poster(_), do: nil

  defp extract_trailer(%{"videoLink" => url}) when is_binary(url), do: String.trim(url)
  defp extract_trailer(_), do: nil

  defp extract_attributes(%{"attributeIds" => attrs}) when is_list(attrs), do: attrs
  defp extract_attributes(_), do: []

  defp extract_event_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_event_id(%{"id" => id}) when is_integer(id), do: Integer.to_string(id)
  defp extract_event_id(_), do: nil

  defp extract_film_id_from_event(%{"filmId" => id}) when is_binary(id), do: id

  defp extract_film_id_from_event(%{"filmId" => id}) when is_integer(id),
    do: Integer.to_string(id)

  defp extract_film_id_from_event(_), do: nil

  defp extract_cinema_id_from_event(%{"cinemaId" => id}) when is_binary(id), do: id

  defp extract_cinema_id_from_event(%{"cinemaId" => id}) when is_integer(id),
    do: Integer.to_string(id)

  defp extract_cinema_id_from_event(_), do: nil

  defp extract_showtime(%{"eventDateTime" => datetime}) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> parse_datetime_fallback(datetime)
    end
  end

  defp extract_showtime(_), do: nil

  # Fallback datetime parser for non-ISO8601 formats
  defp parse_datetime_fallback(datetime_str) do
    # Try parsing with NaiveDateTime then convert to UTC
    case NaiveDateTime.from_iso8601(datetime_str) do
      {:ok, naive_dt} ->
        # Assume Europe/Warsaw timezone for Cinema City Poland
        DateTime.from_naive!(naive_dt, "Europe/Warsaw")

      {:error, _} ->
        Logger.warning("Failed to parse datetime: #{datetime_str}")
        nil
    end
  end

  defp extract_business_day(%{"businessDay" => date}) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> d
      {:error, _} -> nil
    end
  end

  defp extract_business_day(_), do: nil

  defp extract_auditorium(%{"auditorium" => aud}) when is_binary(aud), do: String.trim(aud)
  defp extract_auditorium(_), do: nil

  defp extract_booking_url(%{"bookingLink" => url}) when is_binary(url), do: String.trim(url)
  defp extract_booking_url(_), do: nil

  # Parse language information from attributes
  # Examples: "dubbed-lang-pl", "subbed", "original-lang-en"
  defp parse_language_attributes(attributes) when is_list(attributes) do
    %{
      is_dubbed: Enum.any?(attributes, &String.contains?(&1, "dubbed")),
      is_subbed: Enum.any?(attributes, &String.contains?(&1, "subbed")),
      dubbed_language: extract_language(attributes, "dubbed-lang-"),
      original_language: extract_language(attributes, "original-lang-")
    }
  end

  defp parse_language_attributes(_), do: %{}

  # Extract language code from attribute
  defp extract_language(attributes, prefix) do
    attributes
    |> Enum.find(fn attr -> String.starts_with?(attr, prefix) end)
    |> case do
      nil -> nil
      attr -> String.replace_prefix(attr, prefix, "")
    end
  end

  # Parse format information from attributes
  # Examples: "2d", "3d", "imax", "4dx"
  defp parse_format_attributes(attributes) when is_list(attributes) do
    %{
      is_2d: Enum.member?(attributes, "2d"),
      is_3d: Enum.member?(attributes, "3d"),
      is_imax: Enum.any?(attributes, &String.contains?(&1, "imax")),
      is_4dx: Enum.any?(attributes, &String.contains?(&1, "4dx")),
      is_vip: Enum.any?(attributes, &String.contains?(&1, "vip"))
    }
  end

  defp parse_format_attributes(_), do: %{}

  # Parse genre tags from attributes
  # Examples: "sci-fi", "action", "drama", "horror"
  defp parse_genre_attributes(attributes) when is_list(attributes) do
    known_genres = [
      "action",
      "adventure",
      "animation",
      "comedy",
      "crime",
      "documentary",
      "drama",
      "fantasy",
      "horror",
      "mystery",
      "romance",
      "sci-fi",
      "thriller",
      "western"
    ]

    attributes
    |> Enum.filter(fn attr ->
      Enum.any?(known_genres, &String.contains?(attr, &1))
    end)
  end

  defp parse_genre_attributes(_), do: []

  @doc """
  Validate film data has required fields.
  """
  def validate_film(film) when is_map(film) do
    required = [:cinema_city_film_id, :polish_title]

    missing =
      required
      |> Enum.reject(fn field -> Map.get(film, field) end)

    case missing do
      [] -> {:ok, film}
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  @doc """
  Validate event data has required fields.
  """
  def validate_event(event) when is_map(event) do
    required = [:cinema_city_event_id, :cinema_city_film_id, :showtime]

    missing =
      required
      |> Enum.reject(fn field -> Map.get(event, field) end)

    case missing do
      [] -> {:ok, event}
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end
end
