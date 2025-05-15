defmodule EventasaurusWeb.Services.SearchService do
  @moduledoc """
  Unified search service for Unsplash and TMDb (multi-search).
  Returns grouped results by source.
  """

  alias EventasaurusWeb.Services.UnsplashService
  alias EventasaurusWeb.Services.TmdbService

  def unified_search(query, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 10)

    unsplash = Task.async(fn -> UnsplashService.search_photos(query, page, per_page) end)
    tmdb = Task.async(fn -> TmdbService.search_multi(query, page) end)

    unsplash_results = Task.await(unsplash, 5000)
    tmdb_results = Task.await(tmdb, 5000)

    %{
      unsplash: parse_unsplash(unsplash_results),
      tmdb: parse_tmdb(tmdb_results)
    }
  end

  defp parse_unsplash({:ok, results}), do: results
  defp parse_unsplash(_), do: []

  defp parse_tmdb({:ok, results}), do: results
  defp parse_tmdb(_), do: []
end
