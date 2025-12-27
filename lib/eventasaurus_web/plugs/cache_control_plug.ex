defmodule EventasaurusWeb.Plugs.CacheControlPlug do
  @moduledoc """
  Sets cache control headers for CDN caching with client-side auth hydration.

  ## CDN Caching Strategy

  We cache the SAME HTML for everyone on public pages, regardless of auth state.
  Auth UI is hydrated client-side using Clerk's JavaScript SDK (SignedIn/SignedOut
  components).

  Why we don't differentiate by auth cookies:
  - Cloudflare doesn't vary cache by cookies (unless Enterprise with custom cache keys)
  - Even if we served different headers to authenticated users, they'd still get
    the cached anonymous version
  - The solution is to cache the same page for everyone and let Clerk's client-side
    components hydrate the auth UI after page load

  See: https://github.com/razrfly/eventasaurus/issues/2970

  ## Caching Behavior

  - **Public catalog pages** (`:cacheable_request` assign set):
    - Set-Cookie header is STRIPPED via before_send callback in ConditionalSessionPlug
    - `Cache-Control: public, s-maxage=TTL, max-age=0, must-revalidate`
    - CDN caches the response (no Set-Cookie = Cloudflare respects Cache-Control)
    - Show pages: 48h TTL, Index pages: 1h TTL

  - **Other routes**:
    - `Cache-Control: public, s-maxage=172800, max-age=0, must-revalidate`
    - Note: May still have Set-Cookie which causes Cloudflare to bypass

  ## How Set-Cookie Stripping Works

  The cookie stripping is done via `register_before_send` in ConditionalSessionPlug:

  1. ConditionalSessionPlug runs FIRST, registers a before_send callback
  2. fetch_session runs, Plug.Session registers ITS before_send callback
  3. Response is sent, before_send runs in LIFO order:
     - Plug.Session's callback runs FIRST (adds Set-Cookie)
     - Our callback runs SECOND (strips the session cookie)

  This approach works because:
  - Session is NOT ignored, so LiveView CSRF tokens work correctly
  - Cookie is stripped at the very end, after all session operations complete

  ## Cache TTL Configuration

  TTL values are easily configurable via module attributes:
  - `@show_page_ttl` - Show pages (48 hours = 172800 seconds)
  - `@index_page_ttl` - Index pages (1 hour = 3600 seconds)

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

  ## References

  - GitHub Issue: https://github.com/razrfly/eventasaurus/issues/2970
  - GitHub Issue: https://github.com/razrfly/eventasaurus/issues/2940
  - HTTP Caching: https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching
  """

  import Plug.Conn

  @behaviour Plug

  # =============================================================================
  # CACHE TTL CONFIGURATION (easily adjustable)
  # =============================================================================

  # Show pages: /activities/:slug, /venues/:slug, /performers/:slug, /movies/:id
  # These are relatively static and can be cached longer
  # 48 hours in seconds
  @show_page_ttl 172_800

  # Index pages: /activities, /movies (Phase 3)
  # These change more frequently and need shorter cache
  # 1 hour in seconds
  @index_page_ttl 3_600

  # Default TTL for other cacheable routes
  @default_ttl @show_page_ttl

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    # CDN Caching Strategy: Cache the SAME HTML for everyone on public pages.
    # Auth UI is hydrated client-side using Clerk's JavaScript SDK.
    #
    # We no longer differentiate cache headers based on auth cookies because
    # Cloudflare doesn't vary cache by cookies. Authenticated users would get
    # cached anonymous pages anyway.
    #
    # See: https://github.com/razrfly/eventasaurus/issues/2970
    cond do
      # Cacheable route - use specific TTL if set
      # This is set by ConditionalSessionPlug for allowlisted routes
      # The before_send callback registered by ConditionalSessionPlug will strip
      # the session cookie to enable CDN caching
      conn.assigns[:cacheable_request] ->
        ttl = conn.assigns[:cache_ttl] || @default_ttl
        set_cacheable_headers(conn, ttl)

      # Default - still set cache headers (may be bypassed by Set-Cookie)
      true ->
        set_cacheable_headers(conn, @default_ttl)
    end
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
