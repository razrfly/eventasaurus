defmodule EventasaurusWeb.Plugs.CacheControlPlug do
  @moduledoc """
  Sets cache control headers based on authentication state and route cacheability.

  ## Caching Strategy

  - **Public catalog pages** (`:cacheable_request` + `:readonly_session` assigns set):
    - Set-Cookie header is STRIPPED via before_send callback in ConditionalSessionPlug
    - `Cache-Control: public, s-maxage=TTL, max-age=0, must-revalidate`
    - CDN caches the response (no Set-Cookie = Cloudflare respects Cache-Control)
    - Show pages: 48h TTL, Index pages: 1h TTL

  - **Other anonymous users** (no `__session` cookie, not on catalog route):
    - `Cache-Control: public, s-maxage=172800, max-age=0, must-revalidate`
    - Note: May still have Set-Cookie which causes Cloudflare to bypass

  - **Authenticated users** (has `__session` cookie): No caching
    - `Cache-Control: private, no-store, no-cache, must-revalidate`
    - Every request goes to origin server
    - Cacheable assigns are CLEARED so cookie stripping doesn't happen

  ## How Set-Cookie Stripping Works

  The cookie stripping is done via `register_before_send` in ConditionalSessionPlug:

  1. ConditionalSessionPlug runs FIRST, registers a before_send callback
  2. fetch_session runs, Plug.Session registers ITS before_send callback
  3. Response is sent, before_send runs in LIFO order:
     - Plug.Session's callback runs FIRST (adds Set-Cookie)
     - Our callback runs SECOND (strips the session cookie if still cacheable)

  This approach works because:
  - Session is NOT ignored, so LiveView CSRF tokens work correctly
  - Cookie is stripped at the very end, after all session operations complete
  - Authenticated users have assigns cleared, so stripping doesn't happen

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
      # Authenticated user (production Clerk session) - no caching
      # Clear cacheable assigns so the before_send callback won't strip cookies
      has_session_cookie?(conn) ->
        conn
        |> clear_cacheable_assigns()
        |> set_no_cache_headers()

      # Dev mode authenticated user - no caching
      # This check must be in CacheControlPlug (not ConditionalSessionPlug)
      # because session is only available after maybe_fetch_session runs
      # Clear cacheable assigns so the before_send callback won't strip cookies
      has_dev_mode_login?(conn) ->
        conn
        |> clear_cacheable_assigns()
        |> set_no_cache_headers()

      # Cacheable route with anonymous user - use specific TTL if set
      # This is set by ConditionalSessionPlug for allowlisted routes
      # The before_send callback registered by ConditionalSessionPlug will strip
      # the session cookie since cacheable assigns are still set
      conn.assigns[:cacheable_request] ->
        ttl = conn.assigns[:cache_ttl] || @default_ttl
        set_cacheable_headers(conn, ttl)

      # Default anonymous - still set cache headers (may be bypassed by Set-Cookie)
      true ->
        set_cacheable_headers(conn, @default_ttl)
    end
  end

  # Clear cacheable assigns so the before_send callback won't strip cookies
  # This is called for authenticated users who should have normal session behavior
  defp clear_cacheable_assigns(conn) do
    conn
    |> assign(:cacheable_request, false)
    |> assign(:readonly_session, false)
  end

  # Check if the request has a Clerk session cookie
  defp has_session_cookie?(conn) do
    conn = fetch_cookies(conn)
    cookie_value = conn.cookies["__session"]
    cookie_value != nil and cookie_value != ""
  end

  # Check for dev mode login in session (only relevant in dev environment)
  # This runs AFTER maybe_fetch_session, so session data is available
  # This ensures dev-mode logged-in users don't get cached responses
  defp has_dev_mode_login?(conn) do
    if Mix.env() == :dev do
      # Session should be fetched by now (after maybe_fetch_session in pipeline)
      case conn.private[:plug_session] do
        nil ->
          # Session not fetched - this shouldn't happen in :public pipeline
          false

        _session ->
          # Session exists, check for dev login flag
          get_session(conn, "dev_mode_login") == true
      end
    else
      # In production, there's no dev mode login
      false
    end
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
