defmodule EventasaurusWeb.Plugs.AggregationTypeRedirect do
  @moduledoc """
  Plug to redirect legacy aggregation type URLs to URL-friendly slug URLs.

  This ensures backward compatibility for old custom types that may exist in
  bookmarks, external links, or other references.

  ## Examples

      # Old custom type: /c/krakow/restaurant/week_pl
      # Redirects to:     /c/krakow/food/week_pl

      # Old trivia type:  /c/austin/trivia/pubquiz-pl
      # Redirects to:     /c/austin/social/pubquiz-pl

      # Old movie type:   /c/warsaw/movie/cinema-city
      # Redirects to:     /c/warsaw/movies/cinema-city
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  # Mapping of legacy custom types to URL-friendly slugs
  @legacy_mappings %{
    "restaurant" => "food",
    "movie" => "movies",
    "concert" => "music",
    "trivia" => "social"
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.path_info do
      # City-scoped route: /c/:city_slug/:content_type/:identifier
      ["c", city_slug, content_type, identifier | rest] ->
        redirect_if_legacy(conn, city_slug, content_type, identifier, rest)

      # Multi-city route: /:content_type/:identifier
      [content_type, identifier | rest]
      when content_type in ["restaurant", "movie", "concert", "trivia"] ->
        redirect_legacy_multi_city(conn, content_type, identifier, rest)

      _ ->
        conn
    end
  end

  defp redirect_if_legacy(conn, city_slug, content_type, identifier, rest) do
    case Map.get(@legacy_mappings, content_type) do
      nil ->
        # Not a legacy type, continue
        conn

      new_type ->
        # Build new path with URL-friendly slug
        new_path =
          case rest do
            [] -> "/c/#{city_slug}/#{new_type}/#{identifier}"
            segments -> "/c/#{city_slug}/#{new_type}/#{identifier}/#{Enum.join(segments, "/")}"
          end

        # Preserve query string if present
        new_path_with_query =
          case conn.query_string do
            "" -> new_path
            query -> "#{new_path}?#{query}"
          end

        conn
        |> put_status(:moved_permanently)
        |> redirect(to: new_path_with_query)
        |> halt()
    end
  end

  defp redirect_legacy_multi_city(conn, content_type, identifier, rest) do
    new_type = Map.get(@legacy_mappings, content_type, content_type)

    new_path =
      case rest do
        [] -> "/#{new_type}/#{identifier}"
        segments -> "/#{new_type}/#{identifier}/#{Enum.join(segments, "/")}"
      end

    # Preserve query string if present
    new_path_with_query =
      case conn.query_string do
        "" -> new_path
        query -> "#{new_path}?#{query}"
      end

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: new_path_with_query)
    |> halt()
  end
end
