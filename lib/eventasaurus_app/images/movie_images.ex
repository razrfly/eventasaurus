defmodule EventasaurusApp.Images.MovieImages do
  @moduledoc """
  Get cached movie poster and backdrop URLs from R2 storage.

  Movies cache images on creation via MovieStore.create_movie/1:
  - Poster at position 0
  - Backdrop at position 1

  ## Usage

      # Get poster URL with fallback to original TMDB URL
      url = MovieImages.get_poster_url(movie.id, movie.poster_url)

      # Get backdrop URL with fallback
      url = MovieImages.get_backdrop_url(movie.id, movie.backdrop_url)

      # Batch lookup for multiple movies (avoids N+1)
      poster_urls = MovieImages.get_poster_urls([movie1.id, movie2.id])
      # => %{1 => "https://cdn...", 2 => "https://cdn..."}

      # Batch with fallbacks
      fallbacks = %{movie1.id => movie1.poster_url, movie2.id => movie2.poster_url}
      urls = MovieImages.get_poster_urls_with_fallbacks(fallbacks)
  """

  alias EventasaurusApp.Images.ImageCacheService

  @poster_position 0
  @backdrop_position 1

  # ============================================================================
  # Single Movie Lookups
  # ============================================================================

  @doc """
  Get the cached poster URL for a movie.

  Returns the CDN URL if the image is cached, the fallback URL otherwise,
  or nil if neither exists.

  ## Examples

      iex> MovieImages.get_poster_url(123, "https://tmdb.org/poster.jpg")
      "https://cdn.wombie.com/images/movie/123/0.jpg"

      iex> MovieImages.get_poster_url(999, "https://tmdb.org/poster.jpg")
      "https://tmdb.org/poster.jpg"  # Falls back to original
  """
  @spec get_poster_url(integer(), String.t() | nil) :: String.t() | nil
  def get_poster_url(movie_id, fallback \\ nil) when is_integer(movie_id) do
    ImageCacheService.get_url!("movie", movie_id, @poster_position) || fallback
  end

  @doc """
  Get the cached backdrop URL for a movie.

  Returns the CDN URL if the image is cached, the fallback URL otherwise,
  or nil if neither exists.
  """
  @spec get_backdrop_url(integer(), String.t() | nil) :: String.t() | nil
  def get_backdrop_url(movie_id, fallback \\ nil) when is_integer(movie_id) do
    ImageCacheService.get_url!("movie", movie_id, @backdrop_position) || fallback
  end

  # ============================================================================
  # Batch Lookups (N+1 Prevention)
  # ============================================================================

  @doc """
  Batch get poster URLs for multiple movies.

  Returns a map of `%{movie_id => cdn_url}`. Movies without cached
  posters will not have entries in the map.

  ## Example

      iex> MovieImages.get_poster_urls([1, 2, 3])
      %{1 => "https://cdn...", 2 => "https://cdn..."}  # movie 3 has no cached poster
  """
  @spec get_poster_urls([integer()]) :: %{integer() => String.t()}
  def get_poster_urls([]), do: %{}

  def get_poster_urls(movie_ids) when is_list(movie_ids) do
    get_urls_for_position(movie_ids, @poster_position)
  end

  @doc """
  Batch get backdrop URLs for multiple movies.

  Returns a map of `%{movie_id => cdn_url}`. Movies without cached
  backdrops will not have entries in the map.
  """
  @spec get_backdrop_urls([integer()]) :: %{integer() => String.t()}
  def get_backdrop_urls([]), do: %{}

  def get_backdrop_urls(movie_ids) when is_list(movie_ids) do
    get_urls_for_position(movie_ids, @backdrop_position)
  end

  @doc """
  Batch get poster URLs with fallbacks for multiple movies.

  Takes a map of `%{movie_id => fallback_url}` and returns
  `%{movie_id => effective_url}` preferring cached URLs.

  ## Example

      iex> fallbacks = %{1 => "https://tmdb/1.jpg", 2 => "https://tmdb/2.jpg"}
      iex> MovieImages.get_poster_urls_with_fallbacks(fallbacks)
      %{1 => "https://cdn.wombie.com/...", 2 => "https://tmdb/2.jpg"}
  """
  @spec get_poster_urls_with_fallbacks(%{integer() => String.t() | nil}) ::
          %{integer() => String.t() | nil}
  def get_poster_urls_with_fallbacks(movie_fallbacks) when is_map(movie_fallbacks) do
    get_urls_with_fallbacks_for_position(movie_fallbacks, @poster_position)
  end

  @doc """
  Batch get backdrop URLs with fallbacks for multiple movies.

  Takes a map of `%{movie_id => fallback_url}` and returns
  `%{movie_id => effective_url}` preferring cached URLs.
  """
  @spec get_backdrop_urls_with_fallbacks(%{integer() => String.t() | nil}) ::
          %{integer() => String.t() | nil}
  def get_backdrop_urls_with_fallbacks(movie_fallbacks) when is_map(movie_fallbacks) do
    get_urls_with_fallbacks_for_position(movie_fallbacks, @backdrop_position)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Get cached URLs for a specific position across multiple movies
  defp get_urls_for_position(movie_ids, position) do
    import Ecto.Query
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Images.CachedImage

    from(c in CachedImage,
      where: c.entity_type == "movie",
      where: c.entity_id in ^movie_ids,
      where: c.position == ^position,
      where: c.status == "cached",
      where: not is_nil(c.cdn_url),
      select: {c.entity_id, c.cdn_url}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Get URLs with fallbacks for a specific position
  defp get_urls_with_fallbacks_for_position(movie_fallbacks, position) do
    movie_ids = Map.keys(movie_fallbacks)
    cached_urls = get_urls_for_position(movie_ids, position)

    Map.new(movie_fallbacks, fn {movie_id, fallback} ->
      {movie_id, Map.get(cached_urls, movie_id, fallback)}
    end)
  end
end
