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

  describe "Set-Cookie stripping for cacheable routes" do
    test "strips Set-Cookie header when cacheable_request and readonly_session are set" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> Plug.Conn.assign(:cacheable_request, true)
        |> Plug.Conn.assign(:readonly_session, true)
        |> Plug.Conn.put_resp_header("set-cookie", "test=value; Path=/")
        |> CacheControlPlug.call([])

      # Simulate sending the response to trigger the before_send callback
      conn = Plug.Conn.send_resp(conn, 200, "OK")

      # Set-Cookie should be stripped
      assert get_resp_header(conn, "set-cookie") == []
    end

    test "does not strip Set-Cookie when only cacheable_request is set (no readonly_session)" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> Plug.Conn.assign(:cacheable_request, true)
        # Note: readonly_session is NOT set
        |> Plug.Conn.put_resp_header("set-cookie", "test=value; Path=/")
        |> CacheControlPlug.call([])

      # Simulate sending the response
      conn = Plug.Conn.send_resp(conn, 200, "OK")

      # Set-Cookie should NOT be stripped (readonly_session not set)
      assert get_resp_header(conn, "set-cookie") == ["test=value; Path=/"]
    end

    test "does not strip Set-Cookie for non-cacheable routes" do
      conn =
        :get
        |> conn("/dashboard")
        # Neither cacheable_request nor readonly_session are set
        |> Plug.Conn.put_resp_header("set-cookie", "session=abc123; Path=/")
        |> CacheControlPlug.call([])

      # Simulate sending the response
      conn = Plug.Conn.send_resp(conn, 200, "OK")

      # Set-Cookie should NOT be stripped
      assert get_resp_header(conn, "set-cookie") == ["session=abc123; Path=/"]
    end

    test "does not strip Set-Cookie for authenticated users" do
      conn =
        :get
        |> conn("/activities/some-event")
        |> put_req_cookie("__session", "user-session-token")
        |> Plug.Conn.put_resp_header("set-cookie", "refresh=token; Path=/")
        |> CacheControlPlug.call([])

      # Simulate sending the response
      conn = Plug.Conn.send_resp(conn, 200, "OK")

      # Set-Cookie should NOT be stripped (user is authenticated)
      assert get_resp_header(conn, "set-cookie") == ["refresh=token; Path=/"]
    end
  end
end
