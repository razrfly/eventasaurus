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
          # Mark session as readonly and register callback to strip session cookie
          # Session is still fetched for LiveView CSRF token validation
          # The before_send callback runs AFTER Plug.Session adds the cookie (LIFO order)
          # Note: Dev mode login is checked in CacheControlPlug (after session is fetched)
          conn
          |> assign(:readonly_session, true)
          |> assign(:cacheable_request, true)
          |> assign(:cache_ttl, ttl)
          |> register_cookie_stripping_callback()
        end

      :cacheable ->
        if has_auth_cookie?(conn) do
          conn
        else
          # Mark session as readonly and register callback to strip session cookie
          # Session is still fetched for LiveView CSRF token validation
          # The before_send callback runs AFTER Plug.Session adds the cookie (LIFO order)
          # Note: Dev mode login is checked in CacheControlPlug (after session is fetched)
          conn
          |> assign(:readonly_session, true)
          |> assign(:cacheable_request, true)
          |> register_cookie_stripping_callback()
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

  # Register a before_send callback to strip the session cookie for cacheable requests
  # This callback is registered BEFORE fetch_session, so it runs AFTER Plug.Session's
  # callback (due to LIFO order). This allows us to strip the cookie after it's added.
  #
  # Why this works:
  # 1. ConditionalSessionPlug runs first, registers this callback
  # 2. fetch_session runs, Plug.Session registers its callback
  # 3. Response is sent, before_send runs in LIFO order:
  #    - Plug.Session's callback runs FIRST (adds Set-Cookie)
  #    - Our callback runs SECOND (strips the cookie if still cacheable)
  #
  # The assigns check ensures we don't strip cookies if:
  # - User became authenticated during the request (CacheControlPlug clears assigns)
  # - The request is no longer cacheable for any reason
  defp register_cookie_stripping_callback(conn) do
    register_before_send(conn, fn response_conn ->
      if response_conn.assigns[:cacheable_request] && response_conn.assigns[:readonly_session] do
        strip_session_cookie(response_conn)
      else
        response_conn
      end
    end)
  end

  # Strip the Phoenix session cookie from resp_cookies by removing it entirely
  # This enables CDN caching by preventing ANY Set-Cookie header for the session
  #
  # IMPORTANT: We directly remove from resp_cookies map, NOT using delete_resp_cookie!
  # delete_resp_cookie adds an "expiration" cookie (max-age=0) which still produces
  # a Set-Cookie header. For CDN caching, we need ZERO Set-Cookie headers.
  #
  # The conversion from resp_cookies to set-cookie headers happens AFTER all before_send
  # callbacks run. So at callback time, the cookie exists in resp_cookies but hasn't
  # been converted to a header yet.
  @session_cookie_name "_eventasaurus_key"

  defp strip_session_cookie(conn) do
    require Logger

    if Map.has_key?(conn.resp_cookies, @session_cookie_name) do
      Logger.debug(
        "[ConditionalSession] Stripping session cookie for cacheable request: #{conn.request_path}"
      )

      # Directly remove from resp_cookies map - don't use delete_resp_cookie
      # which would add an expiration cookie that still produces a Set-Cookie header
      %{conn | resp_cookies: Map.delete(conn.resp_cookies, @session_cookie_name)}
    else
      conn
    end
  end
end
