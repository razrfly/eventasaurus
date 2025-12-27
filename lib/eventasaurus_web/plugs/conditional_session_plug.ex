defmodule EventasaurusWeb.Plugs.ConditionalSessionPlug do
  @moduledoc """
  Marks cacheable routes for anonymous users to enable CDN caching.

  This plug enables CDN caching by preventing Set-Cookie headers on public pages
  for users who are not logged in. It does this by marking sessions as "read-only"
  for cacheable routes, which prevents session writes (that cause Set-Cookie headers)
  while still allowing session reads (required for LiveView CSRF tokens).

  ## How it works

  1. Checks if the request path matches a cacheable route pattern
  2. Checks if the user has an auth cookie (`__session` from Clerk)
  3. If cacheable route AND no auth cookie → mark session as readonly (page can be cached)
  4. Otherwise → normal session handling with writes allowed

  ## Important: Session Read vs Write

  - Sessions are ALWAYS fetched (required for LiveView CSRF token validation)
  - For cacheable anonymous requests, session WRITES are prevented (no Set-Cookie)
  - This allows CDN caching while maintaining LiveView WebSocket functionality

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
  Phase 4: Multi-city aggregated content (only implemented types)
  - /social/:identifier
  - /food/:identifier

  ### City-Prefixed Routes (Phase 2+3 completion)
  Show pages (48h TTL):
  - /c/:city_slug/venues/:venue_slug
  - /c/:city_slug/movies/:movie_slug
  - /c/:city_slug/festivals/:container_slug (and other container types)

  Index pages (1h TTL):
  - /c/:city_slug (city homepage)
  - /c/:city_slug/venues
  - /c/:city_slug/festivals (and other container type indexes)

  City aggregated content (1h TTL) - explicit routes only:
  - /c/:city_slug/social/:identifier
  - /c/:city_slug/food/:identifier
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
          # Mark session as readonly to prevent writes (which cause Set-Cookie headers)
          # Session is still fetched for LiveView CSRF token validation
          conn
          |> assign(:readonly_session, true)
          |> assign(:cacheable_request, true)
          |> assign(:cache_ttl, ttl)
        end

      :cacheable ->
        if has_auth_cookie?(conn) do
          conn
        else
          # Mark session as readonly to prevent writes (which cause Set-Cookie headers)
          # Session is still fetched for LiveView CSRF token validation
          conn
          |> assign(:readonly_session, true)
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
      # Phase 3: Index pages (1h TTL) - includes city-prefixed indexes
      index_page?(path) -> {:cacheable, CacheControlPlug.index_page_ttl()}

      # Phase 4: Aggregated content pages (1h TTL) - includes city aggregated content
      aggregated_content_page?(path) -> {:cacheable, CacheControlPlug.index_page_ttl()}

      # Phase 1 + 2: Show pages (48h TTL - default) - includes city-prefixed shows
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
      ~r{^/movies$},

      # Phase 3 completion: City-prefixed index pages
      # /c/:city_slug (city homepage)
      ~r{^/c/[^/]+$},
      # /c/:city_slug/venues
      ~r{^/c/[^/]+/venues$},
      # Container type indexes: /c/:city_slug/:container_type
      # festivals, conferences, tours, series, exhibitions, tournaments
      ~r{^/c/[^/]+/festivals$},
      ~r{^/c/[^/]+/conferences$},
      ~r{^/c/[^/]+/tours$},
      ~r{^/c/[^/]+/series$},
      ~r{^/c/[^/]+/exhibitions$},
      ~r{^/c/[^/]+/tournaments$}
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

      # Phase 2: Venues, Performers, Movies (non-city-prefixed)
      # /venues/:slug
      ~r{^/venues/[^/]+$},
      # /performers/:slug
      ~r{^/performers/[^/]+$},
      # /movies/:identifier (TMDB ID or slug-tmdb_id)
      ~r{^/movies/[^/]+$},

      # Phase 2 completion: City-prefixed show pages
      # /c/:city_slug/venues/:venue_slug
      ~r{^/c/[^/]+/venues/[^/]+$},
      # /c/:city_slug/movies/:movie_slug
      ~r{^/c/[^/]+/movies/[^/]+$},
      # Container detail pages: /c/:city_slug/:container_type/:container_slug
      # festivals, conferences, tours, series, exhibitions, tournaments
      ~r{^/c/[^/]+/festivals/[^/]+$},
      ~r{^/c/[^/]+/conferences/[^/]+$},
      ~r{^/c/[^/]+/tours/[^/]+$},
      ~r{^/c/[^/]+/series/[^/]+$},
      ~r{^/c/[^/]+/exhibitions/[^/]+$},
      ~r{^/c/[^/]+/tournaments/[^/]+$}
    ]

    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, path) end)
  end

  # Phase 4: Aggregated content page patterns (1h cache)
  # These are multi-city aggregated content pages like /social/pubquiz-pl
  # and city-specific aggregated content like /c/warsaw/social/pubquiz-pl
  # Only explicit content types are supported - no catch-all patterns
  defp aggregated_content_page?(path) do
    patterns = [
      # Multi-city aggregated content (non-city-prefixed)
      # Add new content types here as they are implemented
      ~r{^/social/[^/]+$},
      ~r{^/food/[^/]+$},

      # City-specific aggregated content - explicit types only
      # /c/:city_slug/social/:identifier
      ~r{^/c/[^/]+/social/[^/]+$},
      # /c/:city_slug/food/:identifier
      ~r{^/c/[^/]+/food/[^/]+$}
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
