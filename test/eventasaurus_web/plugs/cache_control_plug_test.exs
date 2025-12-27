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

  describe "authenticated users (has __session cookie)" do
    test "sets cache-control header to prevent caching" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("__session", "test-session-token")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "private, no-store, no-cache, must-revalidate"
             ]
    end

    test "sets pragma header to no-cache for HTTP/1.0 compatibility" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("__session", "test-session-token")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "pragma") == ["no-cache"]
    end

    test "sets expires header to 0" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("__session", "test-session-token")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "expires") == ["0"]
    end

    test "does not set vary header" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("__session", "test-session-token")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "vary") == []
    end

    test "ignores :cache_ttl and :cacheable_request assigns when authenticated" do
      conn =
        :get
        |> conn("/activities")
        |> put_req_cookie("__session", "test-session-token")
        |> Plug.Conn.assign(:cacheable_request, true)
        |> Plug.Conn.assign(:cache_ttl, 3600)
        |> CacheControlPlug.call([])

      # Should still be no-cache because user is authenticated
      assert get_resp_header(conn, "cache-control") == [
               "private, no-store, no-cache, must-revalidate"
             ]
    end
  end

  describe "edge cases" do
    test "empty __session cookie is treated as anonymous" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("__session", "")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=172800, max-age=0, must-revalidate"
             ]
    end

    test "other cookies without __session is treated as anonymous" do
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

  describe "session cookie prevention for cacheable routes" do
    # Helper to set up a conn with session initialized
    # This simulates what happens in a real request pipeline
    defp with_session(conn) do
      opts =
        Plug.Session.init(
          store: :cookie,
          key: "_test_key",
          signing_salt: "test_salt",
          encryption_salt: "test_encryption_salt"
        )

      conn
      |> Plug.Session.call(opts)
      |> fetch_session()
    end

    test "sets session to ignore when cacheable_request and readonly_session are set" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> with_session()
        |> Plug.Conn.assign(:cacheable_request, true)
        |> Plug.Conn.assign(:readonly_session, true)
        |> CacheControlPlug.call([])

      # Session should be marked as ignored
      assert conn.private[:plug_session_info] == :ignore
    end

    test "does not set session to ignore when only cacheable_request is set (no readonly_session)" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> with_session()
        |> Plug.Conn.assign(:cacheable_request, true)
        # Note: readonly_session is NOT set
        |> CacheControlPlug.call([])

      # Session should NOT be marked as ignored
      refute conn.private[:plug_session_info] == :ignore
    end

    test "does not set session to ignore for non-cacheable routes" do
      conn =
        :get
        |> conn("/dashboard")
        |> with_session()
        # Neither cacheable_request nor readonly_session are set
        |> CacheControlPlug.call([])

      # Session should NOT be marked as ignored
      refute conn.private[:plug_session_info] == :ignore
    end

    test "does not set session to ignore for authenticated users" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> put_req_cookie("__session", "user-session-token")
        |> with_session()
        |> CacheControlPlug.call([])

      # For authenticated users, the plug takes the no-cache path, not the cacheable path
      # So session should NOT be explicitly ignored (though it doesn't matter since we don't cache)
      refute conn.private[:plug_session_info] == :ignore
    end

    test "session cookie is not written when session is set to ignore" do
      # This test verifies the end-to-end behavior: when session is ignored,
      # Plug.Session's before_send callback won't write a Set-Cookie header
      conn =
        :get
        |> conn("/activities/some-event")
        |> with_session()
        |> Plug.Conn.assign(:cacheable_request, true)
        |> Plug.Conn.assign(:readonly_session, true)
        |> CacheControlPlug.call([])

      # Verify session is marked as ignore
      assert conn.private[:plug_session_info] == :ignore

      # Send response to trigger before_send callbacks
      conn = Plug.Conn.send_resp(conn, 200, "OK")

      # No session cookie should be written
      set_cookie_headers = get_resp_header(conn, "set-cookie")

      # Filter for session cookies (the one we set up with "_test_key")
      session_cookies =
        Enum.filter(set_cookie_headers, fn cookie ->
          String.starts_with?(cookie, "_test_key=")
        end)

      assert session_cookies == []
    end
  end
end
