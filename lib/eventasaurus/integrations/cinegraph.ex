defmodule Eventasaurus.Integrations.Cinegraph do
  @moduledoc """
  Helper functions for generating Cinegraph URLs and integration.

  Cinegraph is a companion movie discovery platform that provides detailed
  film information, cast/crew relationships, and awards tracking.

  ## URL Routes
  Cinegraph supports multiple entry points for viewing movies:
  - `/movies/tmdb/:tmdb_id` - Primary route for external integration (recommended)
  - `/movies/imdb/:imdb_id` - Alternative route using IMDb IDs
  - `/movies/:slug` - Canonical SEO-friendly URL (requires slug knowledge)

  All secondary routes (tmdb/imdb) auto-fetch missing movies and redirect to
  the canonical slug URL, maintaining SEO while providing flexible linking.

  ## Reference
  Implementation details: https://github.com/razrfly/cinegraph/issues/389
  """

  @doc """
  Returns the Cinegraph base URL based on environment.

  Reads from CINEGRAPH_URL env variable, defaults to production.

  ## Examples

      iex> Cinegraph.base_url()
      "https://cinegraph.org"

  """
  def base_url do
    System.get_env("CINEGRAPH_URL") || "https://cinegraph.org"
  end

  @doc """
  Generates Cinegraph movie URL using TMDb ID.

  Returns nil if movie data doesn't contain a TMDb ID.

  ## Examples

      iex> movie = %{tmdb_id: 550}
      iex> Cinegraph.movie_url(movie)
      "https://cinegraph.org/movies/tmdb/550"

      iex> movie = %{tmdb_id: nil}
      iex> Cinegraph.movie_url(movie)
      nil

  """
  def movie_url(%{tmdb_id: tmdb_id}) when is_integer(tmdb_id) and tmdb_id > 0 do
    "#{base_url()}/movies/tmdb/#{tmdb_id}"
  end

  def movie_url(_), do: nil

  @doc """
  Checks if movie data can link to Cinegraph (has TMDb ID).

  ## Examples

      iex> Cinegraph.linkable?(%{tmdb_id: 550})
      true

      iex> Cinegraph.linkable?(%{tmdb_id: nil})
      false

  """
  def linkable?(%{tmdb_id: tmdb_id}) when is_integer(tmdb_id) and tmdb_id > 0, do: true
  def linkable?(_), do: false
end
