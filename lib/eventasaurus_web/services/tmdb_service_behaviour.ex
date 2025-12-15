defmodule EventasaurusWeb.Services.TmdbServiceBehaviour do
  @moduledoc """
  Behaviour for TMDb service implementations.
  This enables mocking of the TmdbService in tests.
  """

  @doc """
  Search for movies, TV shows, and people on TMDb.
  """
  @callback search_multi(String.t(), integer()) ::
              {:ok, list()} | {:error, any()}

  @doc """
  Get detailed movie information by TMDB ID including cast, crew, and images.
  """
  @callback get_movie_details(integer()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Get detailed TV show information by TMDB ID including cast, crew, and images.
  """
  @callback get_tv_details(integer()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Get cached movie details, falling back to API if not cached.
  """
  @callback get_cached_movie_details(integer()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Get popular movies from TMDB, optionally with a page number.
  """
  @callback get_popular_movies(integer()) ::
              {:ok, list()} | {:error, any()}

  @doc """
  Get movies currently in theaters for a specific region.
  """
  @callback get_now_playing(String.t(), integer()) ::
              {:ok, list()} | {:error, any()}

  @doc """
  Get all available translations for a movie by TMDB ID.
  """
  @callback get_movie_translations(integer()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Get upcoming movies for a specific region.
  """
  @callback get_upcoming_movies(String.t(), integer()) ::
              {:ok, list()} | {:error, any()}

  @doc """
  Get alternative titles for a movie by TMDB ID.
  Useful for finding Polish titles of international films.
  """
  @callback get_alternative_titles(integer()) ::
              {:ok, list()} | {:error, any()}
end
