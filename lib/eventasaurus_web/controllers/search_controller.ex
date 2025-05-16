defmodule EventasaurusWeb.SearchController do
  use EventasaurusWeb, :controller
  alias EventasaurusWeb.Services.SearchService

  @doc """
  Unified search endpoint. Accepts a query and returns grouped results from Unsplash and TMDb.
  """
  def unified(conn, params) do
    case Map.get(params, "query") do
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing required 'query' parameter."})
      query ->
        page = safe_parse_positive_integer(Map.get(params, "page", 1), 1)
        per_page = safe_parse_positive_integer(Map.get(params, "per_page", 10), 10)
        results = SearchService.unified_search(query, page: page, per_page: per_page)
        json(conn, results)
    end
  end

  # Helper to safely parse a string/integer to a positive integer, with default fallback
  defp safe_parse_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp safe_parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
  defp safe_parse_positive_integer(_, default), do: default

end
