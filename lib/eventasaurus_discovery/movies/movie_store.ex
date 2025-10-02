defmodule EventasaurusDiscovery.Movies.MovieStore do
  @moduledoc """
  Service for managing movie records - similar to PerformerStore.
  Handles creation, retrieval, and deduplication by TMDB ID.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie

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
  """
  def create_movie(attrs) do
    %Movie{}
    |> Movie.changeset(attrs)
    |> Repo.insert()
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
    |> order_by([{^order_direction, ^order_by_field}])
    |> Repo.all()
  end

  @doc """
  Delete a movie record.
  Note: This will cascade delete associated event_movies records.
  """
  def delete_movie(%Movie{} = movie) do
    Repo.delete(movie)
  end
end
