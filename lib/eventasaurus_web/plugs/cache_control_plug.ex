defmodule EventasaurusWeb.Plugs.CacheControlPlug do
  @moduledoc """
  Sets cache control headers based on authentication state and route cacheability.

  ## Caching Strategy

  - **Public catalog pages** (`:cacheable_request` + `:readonly_session` assigns set):
    - Session is readonly (no writes), Set-Cookie header is STRIPPED before response
    - `Cache-Control: public, s-maxage=TTL, max-age=0, must-revalidate`
    - CDN caches the response (no Set-Cookie = Cloudflare respects Cache-Control)
    - Show pages: 48h TTL, Index pages: 1h TTL

  - **Other anonymous users** (no `__session` cookie, not on catalog route):
    - `Cache-Control: public, s-maxage=172800, max-age=0, must-revalidate`
    - Note: May still have Set-Cookie which causes Cloudflare to bypass

  - **Authenticated users** (has `__session` cookie): No caching
    - `Cache-Control: private, no-store, no-cache, must-revalidate`
    - Every request goes to origin server

  ## Preventing Set-Cookie Headers

  For cacheable catalog routes, this plug calls `configure_session(ignore: true)`
  which tells Plug.Session NOT to write its session cookie. This is critical because:

  1. Cloudflare automatically bypasses cache when Set-Cookie is present
  2. Phoenix adds Set-Cookie via Plug.Session's `before_send` callback
  3. Using `configure_session(ignore: true)` prevents the cookie at the source

  Note: We cannot use `register_before_send` to strip the cookie because callbacks
  run in LIFO order (last registered runs first). Since CacheControlPlug runs after
  `fetch_session`, our callback would run BEFORE Session's callback adds the cookie.

  The session ignoring only occurs when BOTH conditions are true:
  - `conn.assigns[:cacheable_request]` is truthy
  - `conn.assigns[:readonly_session]` is truthy

  ## Cache TTL Configuration

  TTL values are easily configurable via module attributes:
  - `@show_page_ttl` - Show pages (48 hours = 172800 seconds)
  - `@index_page_ttl` - Index pages (1 hour = 3600 seconds)

  ## Why Check Cookie Instead of Auth State?

  This plug runs before authentication is fully processed in the pipeline.
  Checking for the `__session` cookie is sufficient because:

  1. If a browser sends the cookie, they expect authenticated behavior
  2. Even if the cookie is invalid/expired, we shouldn't cache their response
  3. The presence of the cookie is the signal, not its validity

  ## Cloudflare Configuration

  For this to work, Cloudflare must be configured to respect origin headers:
  - Edge TTL: "Use cache-control header if present, bypass cache if not"
  - Browser TTL: "Respect origin TTL"

  ## Usage

  Used in the :public pipeline for CDN-cacheable content:

      pipeline :public do
        plug EventasaurusWeb.Plugs.CacheControlPlug
        # ... other plugs
      end

  Also used in :browser pipeline to set no-cache headers for authenticated users.

  Note: The :public_city pipeline was consolidated into :public. City validation
  is now handled by CityHooks in the live_session on_mount.

  ## References

  - GitHub Issue: https://github.com/razrfly/eventasaurus/issues/2940
  - GitHub Issue: https://github.com/razrfly/eventasaurus/issues/2652
  - GitHub Issue: https://github.com/razrfly/eventasaurus/issues/2651
  - HTTP Caching: https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching
  """

  import Plug.Conn

  @behaviour Plug

  # =============================================================================
  # CACHE TTL CONFIGURATION (easily adjustable)
  # =============================================================================

  # Show pages: /activities/:slug, /venues/:slug, /performers/:slug, /movies/:id
  # These are relatively static and can be cached longer
  @show_page_ttl 172_800  # 48 hours in seconds

  # Index pages: /activities, /movies (Phase 3)
  # These change more frequently and need shorter cache
  @index_page_ttl 3_600  # 1 hour in seconds

  # Default TTL for other cacheable routes
  @default_ttl @show_page_ttl

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    cond do
      # Authenticated user - no caching
      has_session_cookie?(conn) ->
        set_no_cache_headers(conn)

      # Cacheable route with anonymous user - use specific TTL if set
      # This is set by ConditionalSessionPlug for allowlisted routes
      conn.assigns[:cacheable_request] ->
        ttl = conn.assigns[:cache_ttl] || @default_ttl

        conn
        |> set_cacheable_headers(ttl)
        |> prevent_session_cookie()

      # Default anonymous - still set cache headers (may be bypassed by Set-Cookie)
      true ->
        set_cacheable_headers(conn, @default_ttl)
    end
  end

  # Prevent Plug.Session from adding Set-Cookie header for cacheable requests
  # Uses configure_session(ignore: true) which tells Session's before_send callback
  # to skip writing the cookie entirely.
  #
  # This is the correct approach because:
  # 1. before_send callbacks run in LIFO order (last registered runs first)
  # 2. Session registers its callback when fetch_session is called (early)
  # 3. Our callback would run BEFORE Session's, so we can't strip what isn't there yet
  # 4. configure_session(ignore: true) prevents Session from adding the cookie at all
  defp prevent_session_cookie(conn) do
    require Logger

    cacheable = conn.assigns[:cacheable_request]
    readonly = conn.assigns[:readonly_session]

    if cacheable && readonly do
      Logger.debug(
        "[CacheControl] Configuring session to ignore for #{conn.request_path} " <>
          "(preventing Set-Cookie header)"
      )

      configure_session(conn, ignore: true)
    else
      Logger.debug(
        "[CacheControl] NOT ignoring session for #{conn.request_path} " <>
          "cacheable=#{inspect(cacheable)} readonly=#{inspect(readonly)}"
      )

      conn
    end
  end

  # Check if the request has a Clerk session cookie
  defp has_session_cookie?(conn) do
    conn = fetch_cookies(conn)
    cookie_value = conn.cookies["__session"]
    cookie_value != nil and cookie_value != ""
  end

  # Headers for authenticated users - no caching
  defp set_no_cache_headers(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store, no-cache, must-revalidate")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
  end

  # Headers for anonymous users - CDN caching enabled
  defp set_cacheable_headers(conn, ttl) do
    conn
    |> put_resp_header(
      "cache-control",
      "public, s-maxage=#{ttl}, max-age=0, must-revalidate"
    )
    |> put_resp_header("vary", "Accept-Encoding")
  end

  # Expose TTL values for use by ConditionalSessionPlug
  def show_page_ttl, do: @show_page_ttl
  def index_page_ttl, do: @index_page_ttl
end
