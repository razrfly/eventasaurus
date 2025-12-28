defmodule EventasaurusApp.Images.MovieImages do
  @moduledoc """
  Get cached movie poster and backdrop URLs from R2 storage.

  Movies cache images on creation via MovieStore.create_movie/1:
  - Poster with image_type "poster", position 0
  - Backdrop with image_type "backdrop", position 0

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

  alias EventasaurusApp.Images.{ImageCacheService, ImageEnv}

  # ============================================================================
  # Single Movie Lookups
  # ============================================================================

  @doc """
  Get the cached poster URL for a movie.

  Returns the CDN URL if the image is cached, the fallback URL otherwise,
  or nil if neither exists.

  In non-production environments, returns the fallback directly without
  cache lookup (dev uses original URLs, no R2 caching).

  ## Examples

      iex> MovieImages.get_poster_url(123, "https://tmdb.org/poster.jpg")
      "https://cdn.wombie.com/images/movie/123/poster/0.jpg"

      iex> MovieImages.get_poster_url(999, "https://tmdb.org/poster.jpg")
      "https://tmdb.org/poster.jpg"  # Falls back to original
  """
  @spec get_poster_url(integer(), String.t() | nil) :: String.t() | nil
  def get_poster_url(movie_id, fallback \\ nil) when is_integer(movie_id) do
    if ImageEnv.production?() do
      ImageCacheService.get_url!("movie", movie_id, "poster", 0) || fallback
    else
      # In dev/test, skip cache lookup - just use original URL
      fallback
    end
  end

  @doc """
  Get the cached backdrop URL for a movie.

  Returns the CDN URL if the image is cached, the fallback URL otherwise,
  or nil if neither exists.

  In non-production environments, returns the fallback directly.
  """
  @spec get_backdrop_url(integer(), String.t() | nil) :: String.t() | nil
  def get_backdrop_url(movie_id, fallback \\ nil) when is_integer(movie_id) do
    if ImageEnv.production?() do
      ImageCacheService.get_url!("movie", movie_id, "backdrop", 0) || fallback
    else
      fallback
    end
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
    if ImageEnv.production?() do
      get_urls_for_type(movie_ids, "poster")
    else
      # In dev/test, return empty map - fallbacks will be used
      %{}
    end
  end

  @doc """
  Batch get backdrop URLs for multiple movies.

  Returns a map of `%{movie_id => cdn_url}`. Movies without cached
  backdrops will not have entries in the map.

  In non-production, returns empty map (uses fallbacks).
  """
  @spec get_backdrop_urls([integer()]) :: %{integer() => String.t()}
  def get_backdrop_urls([]), do: %{}

  def get_backdrop_urls(movie_ids) when is_list(movie_ids) do
    if ImageEnv.production?() do
      get_urls_for_type(movie_ids, "backdrop")
    else
      %{}
    end
  end

  @doc """
  Batch get poster URLs with fallbacks for multiple movies.

  Takes a map of `%{movie_id => fallback_url}` and returns
  `%{movie_id => effective_url}` preferring cached URLs.

  In non-production, returns fallbacks directly (no cache lookup).

  ## Example

      iex> fallbacks = %{1 => "https://tmdb/1.jpg", 2 => "https://tmdb/2.jpg"}
      iex> MovieImages.get_poster_urls_with_fallbacks(fallbacks)
      %{1 => "https://cdn.wombie.com/...", 2 => "https://tmdb/2.jpg"}
  """
  @spec get_poster_urls_with_fallbacks(%{integer() => String.t() | nil}) ::
          %{integer() => String.t() | nil}
  def get_poster_urls_with_fallbacks(movie_fallbacks) when is_map(movie_fallbacks) do
    if ImageEnv.production?() do
      get_urls_with_fallbacks_for_type(movie_fallbacks, "poster")
    else
      # In dev/test, just return the fallbacks as-is
      movie_fallbacks
    end
  end

  @doc """
  Batch get backdrop URLs with fallbacks for multiple movies.

  Takes a map of `%{movie_id => fallback_url}` and returns
  `%{movie_id => effective_url}` preferring cached URLs.

  In non-production, returns fallbacks directly.
  """
  @spec get_backdrop_urls_with_fallbacks(%{integer() => String.t() | nil}) ::
          %{integer() => String.t() | nil}
  def get_backdrop_urls_with_fallbacks(movie_fallbacks) when is_map(movie_fallbacks) do
    if ImageEnv.production?() do
      get_urls_with_fallbacks_for_type(movie_fallbacks, "backdrop")
    else
      movie_fallbacks
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Get cached URLs for a specific image type across multiple movies
  # Returns the primary (position 0) image of that type for each movie
  defp get_urls_for_type(movie_ids, image_type) do
    import Ecto.Query
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Images.CachedImage

    from(c in CachedImage,
      where: c.entity_type == "movie",
      where: c.entity_id in ^movie_ids,
      where: c.image_type == ^image_type,
      where: c.position == 0,
      where: c.status == "cached",
      where: not is_nil(c.cdn_url),
      select: {c.entity_id, c.cdn_url}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Get URLs with fallbacks for a specific image type
  defp get_urls_with_fallbacks_for_type(movie_fallbacks, image_type) do
    movie_ids = Map.keys(movie_fallbacks)
    cached_urls = get_urls_for_type(movie_ids, image_type)

    Map.new(movie_fallbacks, fn {movie_id, fallback} ->
      {movie_id, Map.get(cached_urls, movie_id, fallback)}
    end)
  end
end
