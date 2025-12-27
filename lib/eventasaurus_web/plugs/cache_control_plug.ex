defmodule EventasaurusWeb.Plugs.CacheControlPlug do
  @moduledoc """
  Sets cache control headers based on authentication state and route cacheability.

  ## Caching Strategy

  - **Show pages** (`:cacheable_request` assign set, `:cache_ttl` not set):
    - Session is skipped, no Set-Cookie header sent
    - `Cache-Control: public, s-maxage=172800, max-age=0, must-revalidate` (48 hours)
    - CDN can cache the response (no Set-Cookie to trigger bypass)

  - **Index pages** (`:cacheable_request` and `:cache_ttl` assigns set):
    - Session is skipped, no Set-Cookie header sent
    - `Cache-Control: public, s-maxage=3600, max-age=0, must-revalidate` (1 hour)
    - CDN caches with shorter TTL for more dynamic content

  - **Other anonymous users** (no `__session` cookie): CDN caching headers set
    - `Cache-Control: public, s-maxage=172800, max-age=0, must-revalidate`
    - Note: May still have Set-Cookie which causes Cloudflare to bypass

  - **Authenticated users** (has `__session` cookie): No caching
    - `Cache-Control: private, no-store, no-cache, must-revalidate`
    - Every request goes to origin server

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

  Add to any pipeline that serves pages with auth-dependent content:

      pipeline :browser do
        plug EventasaurusWeb.Plugs.CacheControlPlug
        # ... other plugs
      end

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
        set_cacheable_headers(conn, ttl)

      # Default anonymous - still set cache headers (may be bypassed by Set-Cookie)
      true ->
        set_cacheable_headers(conn, @default_ttl)
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
