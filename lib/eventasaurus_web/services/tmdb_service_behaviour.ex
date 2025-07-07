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
end
