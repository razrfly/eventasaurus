defmodule EventasaurusWeb.Plugs.AggregationTypeRedirect do
  @moduledoc """
  Plug to redirect legacy aggregation type URLs to schema.org-compliant URLs.

  This ensures backward compatibility when we migrated from custom aggregation types
  (restaurant, movie, concert, events) to schema.org event types (FoodEvent, ScreeningEvent,
  MusicEvent, Event).

  ## Examples

      # Old URL: /c/krakow/restaurant/week_pl
      # New URL: /c/krakow/FoodEvent/week_pl

      # Old URL: /c/warsaw/movie/cinema_city
      # New URL: /c/warsaw/ScreeningEvent/cinema_city
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  # Mapping of legacy aggregation types to schema.org event types
  @legacy_mappings %{
    "restaurant" => "FoodEvent",
    "movie" => "ScreeningEvent",
    "concert" => "MusicEvent",
    "events" => "Event",
    "trivia" => "SocialEvent"
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.path_info do
      # City-scoped route: /c/:city_slug/:content_type/:identifier
      ["c", city_slug, content_type, identifier | rest] ->
        redirect_if_legacy(conn, city_slug, content_type, identifier, rest)

      # Multi-city route: /:content_type/:identifier
      [content_type, identifier | rest] when content_type in ["restaurant", "movie", "concert", "events", "trivia"] ->
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
        # Build new path with schema.org type
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
