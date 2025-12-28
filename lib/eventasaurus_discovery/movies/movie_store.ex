defmodule EventasaurusDiscovery.Movies.MovieStore do
  @moduledoc """
  Service for managing movie records - similar to PerformerStore.
  Handles creation, retrieval, and deduplication by TMDB ID.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusApp.Images.ImageCacheService

  @doc """
  Find an existing movie by TMDB ID or create a new one.
  This prevents duplicate movie entries for the same TMDB movie.
  """
  def find_or_create_by_tmdb_id(tmdb_id, attrs \\ %{}) when is_integer(tmdb_id) do
    case Repo.get_by(Movie, tmdb_id: tmdb_id) do
      nil -> create_movie(Map.put(attrs, :tmdb_id, tmdb_id))
      movie -> {:ok, movie}
    end
  end

  @doc """
  Create a new movie record.
  Automatically queues image caching for poster and backdrop.
  """
  def create_movie(attrs) do
    result =
      %Movie{}
      |> Movie.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, movie} ->
        cache_movie_images(movie)
        {:ok, movie}

      error ->
        error
    end
  end

  # Cache poster (position 0) and backdrop (position 1) images
  defp cache_movie_images(%Movie{} = movie) do
    if movie.poster_url && movie.poster_url != "" do
      ImageCacheService.cache_image("movie", movie.id, 0, movie.poster_url,
        source: "tmdb",
        metadata: %{"tmdb_id" => movie.tmdb_id, "type" => "poster"}
      )
    end

    if movie.backdrop_url && movie.backdrop_url != "" do
      ImageCacheService.cache_image("movie", movie.id, 1, movie.backdrop_url,
        source: "tmdb",
        metadata: %{"tmdb_id" => movie.tmdb_id, "type" => "backdrop"}
      )
    end

    :ok
  end

  @doc """
  Update an existing movie record.
  """
  def update_movie(%Movie{} = movie, attrs) do
    movie
    |> Movie.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Get a movie by its slug.
  """
  def get_movie_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Movie, slug: slug)
  end

  @doc """
  Get a movie by its TMDB ID.
  """
  def get_movie_by_tmdb_id(tmdb_id) when is_integer(tmdb_id) do
    Repo.get_by(Movie, tmdb_id: tmdb_id)
  end

  @doc """
  List movies with optional filters and limits.

  ## Options
    - `:limit` - Maximum number of movies to return (default: 50)
    - `:offset` - Number of movies to skip (default: 0)
    - `:order_by` - Field to order by (default: :inserted_at)
    - `:order_direction` - :asc or :desc (default: :desc)
  """
  def list_movies(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    order_by_field = Keyword.get(opts, :order_by, :inserted_at)
    order_direction = Keyword.get(opts, :order_direction, :desc)

    Movie
    |> limit(^limit)
    |> offset(^offset)
    |> order_by([m], [{^order_direction, field(m, ^order_by_field)}])
    |> Repo.all()
  end

  @doc """
  Delete a movie record.
  Note: This will cascade delete associated event_movies records.
  """
  def delete_movie(%Movie{} = movie) do
    Repo.delete(movie)
  end

  @doc """
  Count total showtimes (occurrences) for a movie in a specific city.

  This counts all occurrences from all public events linked to the movie
  where the venue is in the specified city.
  """
  def count_showtimes_in_city(movie_id, city_id) do
    alias EventasaurusDiscovery.PublicEvents.PublicEvent

    # Get all events for this movie in this city
    events =
      from(pe in PublicEvent,
        join: em in "event_movies",
        on: pe.id == em.event_id,
        join: v in assoc(pe, :venue),
        on: v.city_id == ^city_id,
        where: em.movie_id == ^movie_id,
        select: pe.occurrences
      )
      |> Repo.all()

    # Count occurrences from all events
    events
    |> Enum.flat_map(&extract_occurrence_count/1)
    |> length()
  end

  # Extract occurrences from event occurrences JSON
  defp extract_occurrence_count(nil), do: []

  defp extract_occurrence_count(%{"dates" => dates}) when is_list(dates) do
    dates
  end

  defp extract_occurrence_count(%{"type" => "pattern"}), do: [1]
  defp extract_occurrence_count(_), do: []
end
