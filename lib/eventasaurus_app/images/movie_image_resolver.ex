defmodule EventasaurusApp.Images.MovieImageResolver do
  @moduledoc """
  Unified movie image resolution that works with either Movie structs or rich_data maps.

  This module bridges the gap between:
  1. Movie schema path - images are cached via MovieStore on creation
  2. Rich data path - images come from live TMDB API responses

  It always tries the cache first (by tmdb_id), then falls back to the TMDB URL.

  ## Usage

      # From a Movie struct
      url = MovieImageResolver.get_poster_url(movie)
      url = MovieImageResolver.get_backdrop_url(movie)

      # From rich_data map (TMDB API response)
      url = MovieImageResolver.get_poster_url(rich_data)
      url = MovieImageResolver.get_backdrop_url(rich_data)

      # With explicit TMDB ID and fallback URL
      url = MovieImageResolver.get_poster_url(tmdb_id, fallback_url)
  """

  alias EventasaurusDiscovery.Movies.{Movie, MovieStore}
  alias EventasaurusApp.Images.{MovieImages, ImageEnv}

  # ============================================================================
  # Poster URL Resolution
  # ============================================================================

  @doc """
  Get the best poster URL from any movie data source.

  Checks cache first, falls back to TMDB URL.

  ## Examples

      # From Movie struct
      MovieImageResolver.get_poster_url(movie)

      # From rich_data map
      MovieImageResolver.get_poster_url(rich_data)

      # With explicit TMDB ID
      MovieImageResolver.get_poster_url(12345, "/abc123.jpg")
  """
  @spec get_poster_url(Movie.t() | map() | integer(), String.t() | nil) :: String.t() | nil
  def get_poster_url(source, fallback \\ nil)

  # From Movie struct - use movie.id directly
  def get_poster_url(%Movie{id: id, poster_url: poster_url}, _fallback) do
    MovieImages.get_poster_url(id, poster_url)
  end

  # From TMDB ID with fallback path
  def get_poster_url(tmdb_id, fallback_path) when is_integer(tmdb_id) do
    fallback_url = build_tmdb_url(fallback_path, "w500")
    resolve_cached_url(tmdb_id, "poster", fallback_url)
  end

  # From rich_data map - extract tmdb_id and poster path
  def get_poster_url(rich_data, _fallback) when is_map(rich_data) do
    tmdb_id = extract_tmdb_id(rich_data)
    poster_path = extract_poster_path(rich_data)
    fallback_url = build_tmdb_url(poster_path, "w500")

    if tmdb_id do
      resolve_cached_url(tmdb_id, "poster", fallback_url)
    else
      fallback_url
    end
  end

  def get_poster_url(_, _), do: nil

  # ============================================================================
  # Backdrop URL Resolution
  # ============================================================================

  @doc """
  Get the best backdrop URL from any movie data source.

  Checks cache first, falls back to TMDB URL.

  ## Examples

      # From Movie struct
      MovieImageResolver.get_backdrop_url(movie)

      # From rich_data map
      MovieImageResolver.get_backdrop_url(rich_data)

      # With explicit TMDB ID
      MovieImageResolver.get_backdrop_url(12345, "/abc123.jpg")
  """
  @spec get_backdrop_url(Movie.t() | map() | integer(), String.t() | nil) :: String.t() | nil
  def get_backdrop_url(source, fallback \\ nil)

  # From Movie struct - use movie.id directly
  def get_backdrop_url(%Movie{id: id, backdrop_url: backdrop_url}, _fallback) do
    MovieImages.get_backdrop_url(id, backdrop_url)
  end

  # From TMDB ID with fallback path
  def get_backdrop_url(tmdb_id, fallback_path) when is_integer(tmdb_id) do
    fallback_url = build_tmdb_url(fallback_path, "w1280")
    resolve_cached_url(tmdb_id, "backdrop", fallback_url)
  end

  # From rich_data map - extract tmdb_id and backdrop path
  def get_backdrop_url(rich_data, _fallback) when is_map(rich_data) do
    tmdb_id = extract_tmdb_id(rich_data)
    backdrop_path = extract_backdrop_path(rich_data)
    fallback_url = build_tmdb_url(backdrop_path, "w1280")

    if tmdb_id do
      resolve_cached_url(tmdb_id, "backdrop", fallback_url)
    else
      fallback_url
    end
  end

  def get_backdrop_url(_, _), do: nil

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Resolve cached URL by looking up the movie by tmdb_id, then checking cache
  defp resolve_cached_url(tmdb_id, image_type, fallback_url) do
    # In non-production, skip cache lookup
    if not ImageEnv.production?() do
      fallback_url
    else
      # Look up the movie by tmdb_id to get the internal ID
      case MovieStore.get_movie_by_tmdb_id(tmdb_id) do
        %Movie{id: movie_id} ->
          # We have a cached movie - check for cached image
          case image_type do
            "poster" -> MovieImages.get_poster_url(movie_id, fallback_url)
            "backdrop" -> MovieImages.get_backdrop_url(movie_id, fallback_url)
            _ -> fallback_url
          end

        nil ->
          # No cached movie - use fallback
          fallback_url
      end
    end
  end

  # Extract TMDB ID from various rich_data structures
  defp extract_tmdb_id(rich_data) when is_map(rich_data) do
    # Try different paths where tmdb_id might be stored
    cond do
      is_integer(rich_data["id"]) -> rich_data["id"]
      is_integer(rich_data[:id]) -> rich_data[:id]
      is_integer(rich_data["tmdb_id"]) -> rich_data["tmdb_id"]
      is_integer(rich_data[:tmdb_id]) -> rich_data[:tmdb_id]
      true -> nil
    end
  end

  # Extract poster path from rich_data
  defp extract_poster_path(rich_data) when is_map(rich_data) do
    # Try structured path first (media.images.posters)
    case get_in(rich_data, ["media", "images", "posters"]) do
      [first | _] when is_map(first) ->
        first["file_path"] || first[:file_path]

      _ ->
        # Fall back to direct poster_path
        rich_data["poster_path"] || rich_data[:poster_path]
    end
  end

  # Extract backdrop path from rich_data
  defp extract_backdrop_path(rich_data) when is_map(rich_data) do
    # Try structured path first (media.images.backdrops)
    case get_in(rich_data, ["media", "images", "backdrops"]) do
      [first | _] when is_map(first) ->
        first["file_path"] || first[:file_path]

      _ ->
        # Fall back to direct backdrop_path
        rich_data["backdrop_path"] || rich_data[:backdrop_path]
    end
  end

  # Build a TMDB image URL from a path
  defp build_tmdb_url(nil, _size), do: nil
  defp build_tmdb_url("", _size), do: nil

  defp build_tmdb_url(path, size) when is_binary(path) do
    EventasaurusWeb.Services.MovieConfig.build_image_url(path, size)
  end
end
