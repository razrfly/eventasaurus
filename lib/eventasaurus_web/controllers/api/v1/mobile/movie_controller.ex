defmodule EventasaurusWeb.Api.V1.Mobile.MovieController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.Movies.MovieStore
  alias EventasaurusDiscovery.Movies.MovieStats
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusWeb.Utils.TimezoneUtils
  alias EventasaurusApp.Images.MovieImages
  alias EventasaurusApp.Repo
  alias Eventasaurus.CDN

  import Ecto.Query

  @cdn_poster_opts [width: 300, height: 450, fit: "cover", quality: 85]

  @doc """
  GET /api/v1/mobile/movies

  Returns movies currently showing with stats and city data.
  Supports search filtering and limit.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    search = params["search"]
    limit = parse_int(params["limit"], 24)

    movies = MovieStats.list_now_showing_movies(limit: limit, search: search)
    movie_count = MovieStats.count_now_showing_movies() || 0
    screening_count = MovieStats.count_upcoming_screenings() || 0
    cities = MovieStats.list_cities_with_movies(limit: 8)

    json(conn, %{
      movies: Enum.map(movies, &serialize_movie_list_item/1),
      stats: %{
        movie_count: movie_count,
        screening_count: screening_count,
        city_count: length(cities)
      },
      cities: Enum.map(cities, &serialize_city_with_movies/1)
    })
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"slug" => slug} = params) do
    case MovieStore.get_movie_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Movie not found"})

      movie ->
        city_id = parse_int(params["city_id"])
        now = DateTime.utc_now()
        screenings = fetch_screenings(movie.id, city_id)
        venues = build_venue_groups(screenings, now)

        total_showtimes = Enum.reduce(venues, 0, fn v, acc -> acc + length(v.showtimes) end)

        json(conn, %{
          movie: serialize_movie(movie),
          venues: Enum.map(venues, &serialize_venue_group(&1, now)),
          meta: %{
            total_venues: length(venues),
            total_showtimes: total_showtimes
          }
        })
    end
  end

  # Fetch all screenings for this movie — no starts_at filter.
  # Showtimes live in the occurrences JSONB column, not starts_at.
  defp fetch_screenings(movie_id, city_id) do
    query =
      from(pe in PublicEvent,
        join: em in "event_movies",
        on: pe.id == em.event_id,
        join: v in assoc(pe, :venue),
        where: em.movie_id == ^movie_id,
        order_by: [asc: pe.starts_at],
        preload: [venue: :city_ref]
      )

    query = if city_id, do: where(query, [pe, em, v], v.city_id == ^city_id), else: query

    Repo.all(query)
  end

  # Group events by venue and extract showtimes from occurrences JSONB.
  # Returns both upcoming and recent past, matching the web behavior.
  defp build_venue_groups(screenings, now) do
    screenings
    |> Enum.group_by(& &1.venue.id)
    |> Enum.map(fn {_venue_id, events} ->
      first_event = List.first(events)
      venue = first_event.venue

      showtimes =
        events
        |> Enum.flat_map(&extract_occurrences(&1))
        |> Enum.sort_by(& &1.datetime, DateTime)

      %{
        venue: venue,
        event_slug: first_event.slug,
        showtimes: showtimes,
        upcoming_count:
          Enum.count(showtimes, fn s -> DateTime.compare(s.datetime, now) == :gt end)
      }
    end)
    |> Enum.reject(fn group -> group.showtimes == [] end)
    # Sort: venues with upcoming screenings first, then by name
    |> Enum.sort_by(fn group ->
      {if(group.upcoming_count > 0, do: 0, else: 1), group.venue.name}
    end)
  end

  # Extract all occurrences from a single event's JSONB data.
  # Note: Venue association is :city_ref (not :city), so we resolve timezone
  # directly from venue.city_ref rather than using TimezoneUtils.get_event_timezone
  # which pattern-matches on the :city key.
  defp extract_occurrences(event) do
    timezone =
      case event.venue do
        %{city_ref: %{timezone: tz}} when is_binary(tz) and tz != "" -> tz
        _ -> TimezoneUtils.default_timezone()
      end

    case get_in(event.occurrences || %{}, ["dates"]) do
      dates when is_list(dates) ->
        dates
        |> Enum.map(fn date_info ->
          with {:ok, date} <- Date.from_iso8601(date_info["date"] || ""),
               {:ok, time} <- parse_time_string(date_info["time"]) do
            case DateTime.new(date, time, timezone) do
              {:ok, dt} ->
                %{
                  date: date,
                  time_str: date_info["time"],
                  label: date_info["label"],
                  datetime: dt
                }

              {:ambiguous, dt, _} ->
                %{
                  date: date,
                  time_str: date_info["time"],
                  label: date_info["label"],
                  datetime: dt
                }

              {:gap, _, after_dt} ->
                %{
                  date: date,
                  time_str: date_info["time"],
                  label: date_info["label"],
                  datetime: after_dt
                }

              _ ->
                nil
            end
          else
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp serialize_venue_group(group, now) do
    %{
      venue: %{
        name: group.venue.name || "Unknown Venue",
        address: group.venue.address,
        lat: group.venue.latitude,
        lng: group.venue.longitude
      },
      event_slug: group.event_slug,
      upcoming_count: group.upcoming_count,
      showtimes:
        Enum.map(group.showtimes, fn s ->
          %{
            date: Date.to_iso8601(s.date),
            time: s.time_str,
            label: s.label,
            format: extract_format(s.label),
            datetime: s.datetime,
            is_upcoming: DateTime.compare(s.datetime, now) == :gt
          }
        end)
    }
  end

  defp parse_time_string(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [hour_str, minute_str] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str) do
          Time.new(hour, minute, 0)
        else
          _ -> {:error, :invalid_time}
        end

      _ ->
        {:error, :invalid_time}
    end
  end

  defp parse_time_string(nil), do: {:ok, ~T[20:00:00]}
  defp parse_time_string(_), do: {:error, :invalid_time}

  defp serialize_movie(movie) do
    genres =
      case movie.metadata do
        %{"genres" => genres} when is_list(genres) ->
          Enum.map(genres, fn
            %{"name" => name} -> name
            name when is_binary(name) -> name
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    md = movie.metadata || %{}

    vote_average =
      case md["vote_average"] do
        v when is_number(v) and v > 0 -> v
        _ -> nil
      end

    tagline =
      case md["tagline"] do
        t when is_binary(t) and t != "" -> t
        _ -> nil
      end

    cast =
      case get_in(md, ["credits", "cast"]) do
        cast when is_list(cast) ->
          cast
          |> Enum.filter(fn member -> is_integer(member["id"]) end)
          |> Enum.take(15)
          |> Enum.map(fn member ->
            profile_path = member["profile_path"]

            %{
              id: member["id"],
              name: member["name"],
              character: member["character"],
              profile_url:
                if(is_binary(profile_path) && profile_path != "",
                  do: "https://image.tmdb.org/t/p/w185#{profile_path}",
                  else: nil
                )
            }
          end)

        _ ->
          []
      end

    %{
      title: movie.title,
      slug: movie.slug,
      overview: movie.overview,
      poster_url: movie.poster_url,
      backdrop_url: movie.backdrop_url,
      release_date: movie.release_date,
      runtime: movie.runtime,
      genres: genres,
      vote_average: vote_average,
      tagline: tagline,
      cast: cast,
      tmdb_id: movie.tmdb_id,
      imdb_id: movie.imdb_id
    }
  end

  defp extract_format(label) when is_binary(label) do
    label_lower = String.downcase(label)

    cond do
      String.contains?(label_lower, "imax") -> "IMAX"
      String.contains?(label_lower, "4dx") -> "4DX"
      String.contains?(label_lower, "3d") -> "3D"
      String.contains?(label_lower, "2d") -> "2D"
      true -> nil
    end
  end

  defp extract_format(_), do: nil

  defp parse_int(nil), do: nil

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(_), do: nil

  # --- Movie list serializers ---

  defp serialize_movie_list_item(%{
         movie: movie,
         city_count: city_count,
         screening_count: screening_count,
         next_screening: next_screening
       }) do
    poster_url = resolve_poster_url(movie)

    genres =
      case movie.metadata do
        %{"genres" => genres} when is_list(genres) ->
          Enum.map(genres, fn
            %{"name" => name} -> name
            name when is_binary(name) -> name
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    vote_average =
      case movie.metadata do
        %{"vote_average" => v} when is_number(v) and v > 0 -> v
        _ -> nil
      end

    release_year =
      case movie.release_date do
        %Date{year: year} -> Integer.to_string(year)
        _ -> nil
      end

    %{
      slug: movie.slug,
      title: movie.title,
      poster_url: poster_url,
      release_date: release_year,
      runtime: movie.runtime,
      genres: genres,
      vote_average: vote_average,
      city_count: city_count,
      screening_count: screening_count,
      next_screening: next_screening
    }
  end

  defp serialize_city_with_movies(%{
         city: city,
         movie_count: movie_count,
         screening_count: screening_count
       }) do
    %{
      name: city.name,
      slug: city.slug,
      movie_count: movie_count,
      screening_count: screening_count
    }
  end

  defp resolve_poster_url(movie) do
    url = MovieImages.get_poster_url(movie.id, movie.poster_url)

    case url do
      nil ->
        nil

      url ->
        case CDN.url(url, @cdn_poster_opts) do
          ^url -> ensure_https(url)
          cdn_url -> cdn_url
        end
    end
  end

  defp ensure_https("http://" <> rest), do: "https://" <> rest
  defp ensure_https(url), do: url

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} when num > 0 -> num
      _ -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val) and val > 0, do: val
  defp parse_int(_, default), do: default
end
