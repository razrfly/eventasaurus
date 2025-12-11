defmodule EventasaurusWeb.Plugs.CacheControlPlug do
  @moduledoc """
  Sets cache control headers based on authentication state.

  ## Caching Strategy

  - **Anonymous users** (no `__session` cookie): CDN caches for 12 hours
    - `Cache-Control: public, s-maxage=43200, max-age=0, must-revalidate`
    - CDN serves cached content, browser always revalidates with CDN

  - **Authenticated users** (has `__session` cookie): No caching
    - `Cache-Control: private, no-store, no-cache, must-revalidate`
    - Every request goes to origin server

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

  - GitHub Issue: https://github.com/razrfly/eventasaurus/issues/2652
  - GitHub Issue: https://github.com/razrfly/eventasaurus/issues/2651
  - HTTP Caching: https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching
  """

  import Plug.Conn

  @behaviour Plug

  # CDN cache duration for anonymous users (12 hours in seconds)
  @anonymous_cdn_ttl 43200

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if has_session_cookie?(conn) do
      set_no_cache_headers(conn)
    else
      set_cacheable_headers(conn)
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
  defp set_cacheable_headers(conn) do
    conn
    |> put_resp_header("cache-control", "public, s-maxage=#{@anonymous_cdn_ttl}, max-age=0, must-revalidate")
    |> put_resp_header("vary", "Accept-Encoding")
  end
end
