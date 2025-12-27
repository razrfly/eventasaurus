defmodule EventasaurusWeb.Plugs.ConditionalSessionPlug do
  @moduledoc """
  Conditionally skips session initialization for cacheable routes with anonymous users.

  This plug enables CDN caching by preventing Set-Cookie headers on public pages
  for users who are not logged in.

  ## How it works

  1. Checks if the request path matches a cacheable route pattern
  2. Checks if the user has an auth cookie (`__session` from Clerk)
  3. If cacheable route AND no auth cookie → skip session (page can be cached)
  4. Otherwise → normal session handling

  ## Safety

  - Uses an allowlist approach: only explicitly listed patterns can be cached
  - Any route with `__session` cookie is never cached
  - New routes default to NOT cached (must be added to allowlist)

  ## Cacheable Routes

  ### Show Pages (48h TTL)
  Phase 1: Activities show pages
  - /activities/:slug
  - /activities/:slug/:date_slug

  Phase 2: Venues, Performers, Movies show pages
  - /venues/:slug
  - /performers/:slug
  - /movies/:identifier

  ### Index Pages (1h TTL)
  Phase 3: Index/listing pages
  - /activities
  - /movies

  ### Aggregated Content Pages (1h TTL)
  Phase 4: Multi-city aggregated content
  - /social/:identifier
  - /food/:identifier
  - /music/:identifier
  - /happenings/:identifier
  - /comedy/:identifier
  - /dance/:identifier
  - /classes/:identifier
  - /festivals/:identifier
  - /sports/:identifier
  - /theater/:identifier
  """

  import Plug.Conn

  alias EventasaurusWeb.Plugs.CacheControlPlug

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case route_cache_config(conn.request_path) do
      {:cacheable, ttl} when not is_nil(ttl) ->
        if has_auth_cookie?(conn) do
          conn
        else
          conn
          |> assign(:skip_session, true)
          |> assign(:cacheable_request, true)
          |> assign(:cache_ttl, ttl)
        end

      :cacheable ->
        if has_auth_cookie?(conn) do
          conn
        else
          conn
          |> assign(:skip_session, true)
          |> assign(:cacheable_request, true)
        end

      :not_cacheable ->
        conn
    end
  end

  # Returns cache configuration for a route:
  # - {:cacheable, ttl} for index pages (with specific TTL)
  # - :cacheable for show pages (uses default TTL)
  # - :not_cacheable for everything else
  defp route_cache_config(path) do
    cond do
      # Phase 3: Index pages (1h TTL)
      index_page?(path) -> {:cacheable, CacheControlPlug.index_page_ttl()}

      # Phase 4: Aggregated content pages (1h TTL)
      aggregated_content_page?(path) -> {:cacheable, CacheControlPlug.index_page_ttl()}

      # Phase 1 + 2: Show pages (48h TTL - default)
      show_page?(path) -> :cacheable

      # Everything else
      true -> :not_cacheable
    end
  end

  # Phase 3: Index page patterns (1h cache)
  defp index_page?(path) do
    patterns = [
      # /activities (index)
      ~r{^/activities$},
      # /movies (index)
      ~r{^/movies$}
    ]

    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, path) end)
  end

  # Phase 1 + 2: Show page patterns (48h cache)
  defp show_page?(path) do
    patterns = [
      # Phase 1: Activities
      # /activities/:slug
      ~r{^/activities/[^/]+$},
      # /activities/:slug/:date_slug
      ~r{^/activities/[^/]+/[^/]+$},

      # Phase 2: Venues, Performers, Movies
      # /venues/:slug
      ~r{^/venues/[^/]+$},
      # /performers/:slug
      ~r{^/performers/[^/]+$},
      # /movies/:identifier (TMDB ID or slug-tmdb_id)
      ~r{^/movies/[^/]+$}
    ]

    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, path) end)
  end

  # Phase 4: Aggregated content page patterns (1h cache)
  # These are multi-city aggregated content pages like /social/pubquiz-pl
  defp aggregated_content_page?(path) do
    patterns = [
      # /social/:identifier
      ~r{^/social/[^/]+$},
      # /food/:identifier
      ~r{^/food/[^/]+$},
      # /music/:identifier
      ~r{^/music/[^/]+$},
      # /happenings/:identifier
      ~r{^/happenings/[^/]+$},
      # /comedy/:identifier
      ~r{^/comedy/[^/]+$},
      # /dance/:identifier
      ~r{^/dance/[^/]+$},
      # /classes/:identifier
      ~r{^/classes/[^/]+$},
      # /festivals/:identifier
      ~r{^/festivals/[^/]+$},
      # /sports/:identifier
      ~r{^/sports/[^/]+$},
      # /theater/:identifier
      ~r{^/theater/[^/]+$}
    ]

    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, path) end)
  end

  defp has_auth_cookie?(conn) do
    # Fetch cookies if not already fetched
    conn = fetch_cookies(conn)
    cookie = conn.cookies["__session"]
    cookie != nil and cookie != ""
  end
end
