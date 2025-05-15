defmodule EventasaurusWeb.SearchController do
  use EventasaurusWeb, :controller
  alias EventasaurusWeb.Services.SearchService

  @doc """
  Unified search endpoint. Accepts a query and returns grouped results from Unsplash and TMDb.
  """
  def unified(conn, %{"query" => query} = params) do
    page = Map.get(params, "page", 1)
    per_page = Map.get(params, "per_page", 10)
    results = SearchService.unified_search(query, page: page, per_page: per_page)
    json(conn, results)
  end
end
