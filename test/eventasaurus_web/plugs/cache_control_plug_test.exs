defmodule EventasaurusWeb.Plugs.CacheControlPlugTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias EventasaurusWeb.Plugs.CacheControlPlug

  describe "TTL configuration" do
    test "show_page_ttl returns 48 hours in seconds" do
      assert CacheControlPlug.show_page_ttl() == 172_800
    end

    test "index_page_ttl returns 1 hour in seconds" do
      assert CacheControlPlug.index_page_ttl() == 3600
    end
  end

  describe "anonymous users with default TTL (no __session cookie, no :cache_ttl assign)" do
    test "sets cache-control header with 48h TTL" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=172800, max-age=0, must-revalidate"
             ]
    end

    test "sets vary header to Accept-Encoding" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "vary") == ["Accept-Encoding"]
    end

    test "does not set pragma header" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "pragma") == []
    end

    test "does not set expires header" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "expires") == []
    end
  end

  describe "cacheable requests with custom TTL (index pages)" do
    test "uses custom :cache_ttl assign when set" do
      conn =
        :get
        |> conn("/activities")
        |> Plug.Conn.assign(:cacheable_request, true)
        |> Plug.Conn.assign(:cache_ttl, 3600)
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=3600, max-age=0, must-revalidate"
             ]
    end

    test "uses default TTL when :cacheable_request is set but no :cache_ttl" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> Plug.Conn.assign(:cacheable_request, true)
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=172800, max-age=0, must-revalidate"
             ]
    end
  end

  # CDN Caching Strategy (Issue #2970):
  # We no longer differentiate cache headers by auth state because Cloudflare
  # doesn't vary cache by cookies. Instead, we cache the same HTML for everyone
  # and use Clerk's JavaScript SDK to hydrate auth UI client-side.
  #
  # The old "authenticated users" tests have been removed since we now serve
  # the same cache headers regardless of whether __session cookie is present.

  describe "edge cases - cookies don't affect caching (Issue #2970)" do
    # Since Cloudflare doesn't vary cache by cookies, we cache the same HTML
    # for everyone. Auth UI is hydrated client-side using Clerk.

    test "requests with __session cookie get same cache headers as anonymous" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("__session", "valid-session-token")
        |> CacheControlPlug.call([])

      # Same headers as anonymous - CDN caches for everyone
      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=172800, max-age=0, must-revalidate"
             ]
    end

    test "empty __session cookie gets cacheable headers" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("__session", "")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=172800, max-age=0, must-revalidate"
             ]
    end

    test "other cookies get cacheable headers" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("other_cookie", "some-value")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=172800, max-age=0, must-revalidate"
             ]
    end
  end

  describe "cacheable assigns management (Issue #2970)" do
    # With client-side Clerk hydration, we no longer clear assigns based on auth cookies.
    # CacheControlPlug just reads the assigns set by ConditionalSessionPlug.

    test "preserves cacheable assigns on cacheable routes regardless of auth cookies" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> put_req_cookie("__session", "user-session-token")
        |> Plug.Conn.assign(:cacheable_request, true)
        |> CacheControlPlug.call([])

      # Assigns are preserved - we cache for everyone with client-side hydration
      assert conn.assigns[:cacheable_request] == true
    end

    test "preserves cacheable assigns for anonymous users on cacheable routes" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> Plug.Conn.assign(:cacheable_request, true)
        |> CacheControlPlug.call([])

      # Cacheable assigns should be preserved
      assert conn.assigns[:cacheable_request] == true
    end

    test "does not set cacheable assigns for non-cacheable routes" do
      conn =
        :get
        |> conn("/dashboard")
        # No cacheable assigns set
        |> CacheControlPlug.call([])

      # No cacheable assigns should be set
      refute Map.has_key?(conn.assigns, :cacheable_request)
    end
  end
end
