defmodule EventasaurusDiscovery.Movies.MovieStats do
  @moduledoc """
  Context module for movie statistics and discovery queries.
  Provides aggregated movie data for the movies index page.
  """
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City

  alias EventasaurusDiscovery.PublicEvents.EventMovie

  # Use read replica for all read operations in this module
  defp repo, do: Repo.replica()

  @doc """
  Lists movies that are currently showing (have future screenings).
  Returns movies with city counts, screening counts, and next screening date.

  ## Options
    * `:limit` - Maximum number of movies to return (default: 24)
    * `:min_screenings` - Minimum number of screenings required (default: 1)
    * `:search` - Search term for movie title (fuzzy match)

  ## Returns
  List of maps with:
    * `:movie` - The Movie struct
    * `:city_count` - Number of distinct cities showing this movie
    * `:screening_count` - Total number of upcoming screenings
    * `:next_screening` - DateTime of the next screening
  """
  @spec list_now_showing_movies(keyword()) :: [map()]
  def list_now_showing_movies(opts \\ []) do
    limit = Keyword.get(opts, :limit, 24)
    min_screenings = Keyword.get(opts, :min_screenings, 1)
    search = Keyword.get(opts, :search)
    now = NaiveDateTime.utc_now()

    query =
      from(m in Movie,
        join: em in EventMovie,
        on: em.movie_id == m.id,
        join: pe in PublicEvent,
        on: pe.id == em.event_id,
        join: v in Venue,
        on: v.id == pe.venue_id,
        where: pe.starts_at > ^now or (not is_nil(pe.ends_at) and pe.ends_at > ^now),
        group_by: m.id,
        having: count(pe.id) >= ^min_screenings,
        order_by: [desc: count(v.city_id, :distinct), desc: count(pe.id)],
        limit: ^limit,
        select: %{
          movie: m,
          city_count: count(v.city_id, :distinct),
          screening_count: count(pe.id),
          next_screening: min(pe.starts_at)
        }
      )

    query =
      if search && search != "" do
        search_term = "%#{search}%"
        from([m, em, pe, v] in query, where: ilike(m.title, ^search_term))
      else
        query
      end

    repo().all(query)
  end

  @doc """
  Lists cities that have movie screenings, ordered by movie count.

  ## Options
    * `:limit` - Maximum number of cities to return (default: 8)
    * `:min_movies` - Minimum number of movies required (default: 1)

  ## Returns
  List of maps with:
    * `:city` - The City struct (preloaded with country)
    * `:movie_count` - Number of distinct movies showing in this city
    * `:screening_count` - Total number of upcoming movie screenings
  """
  @spec list_cities_with_movies(keyword()) :: [map()]
  def list_cities_with_movies(opts \\ []) do
    limit = Keyword.get(opts, :limit, 8)
    min_movies = Keyword.get(opts, :min_movies, 1)
    now = NaiveDateTime.utc_now()

    # First get the city stats
    city_stats =
      from(c in City,
        join: v in Venue,
        on: v.city_id == c.id,
        join: pe in PublicEvent,
        on: pe.venue_id == v.id,
        join: em in EventMovie,
        on: em.event_id == pe.id,
        where: c.discovery_enabled == true,
        where: pe.starts_at > ^now or (not is_nil(pe.ends_at) and pe.ends_at > ^now),
        group_by: c.id,
        having: count(em.movie_id, :distinct) >= ^min_movies,
        order_by: [desc: count(em.movie_id, :distinct)],
        limit: ^limit,
        select: %{
          city_id: c.id,
          movie_count: count(em.movie_id, :distinct),
          screening_count: count(pe.id)
        }
      )
      |> repo().all()

    # Batch load cities with countries to avoid N+1
    city_ids = Enum.map(city_stats, & &1.city_id)

    cities_by_id =
      from(c in City,
        where: c.id in ^city_ids,
        preload: [:country]
      )
      |> repo().all()
      |> Map.new(fn city -> {city.id, city} end)

    # Combine stats with city structs
    city_stats
    |> Enum.map(fn stat ->
      %{
        city: Map.get(cities_by_id, stat.city_id),
        movie_count: stat.movie_count,
        screening_count: stat.screening_count
      }
    end)
    |> Enum.reject(fn stat -> is_nil(stat.city) end)
  end

  @doc """
  Gets the total count of movies currently showing.
  """
  @spec count_now_showing_movies() :: non_neg_integer() | nil
  def count_now_showing_movies do
    now = NaiveDateTime.utc_now()

    from(m in Movie,
      join: em in EventMovie,
      on: em.movie_id == m.id,
      join: pe in PublicEvent,
      on: pe.id == em.event_id,
      where: pe.starts_at > ^now or (not is_nil(pe.ends_at) and pe.ends_at > ^now),
      select: count(m.id, :distinct)
    )
    |> repo().one()
  end

  @doc """
  Gets the total count of upcoming movie screenings.
  """
  @spec count_upcoming_screenings() :: non_neg_integer() | nil
  def count_upcoming_screenings do
    now = NaiveDateTime.utc_now()

    from(pe in PublicEvent,
      join: em in EventMovie,
      on: em.event_id == pe.id,
      where: pe.starts_at > ^now or (not is_nil(pe.ends_at) and pe.ends_at > ^now),
      select: count(pe.id)
    )
    |> repo().one()
  end
end
