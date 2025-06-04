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

    # Use the actual service functions
    unsplash_results = UnsplashService.search_photos(query, page, per_page)
    tmdb_results = TmdbService.search_multi(query, page)

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
