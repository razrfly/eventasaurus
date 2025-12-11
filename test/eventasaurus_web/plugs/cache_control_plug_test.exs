defmodule EventasaurusWeb.Plugs.CacheControlPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias EventasaurusWeb.Plugs.CacheControlPlug

  describe "anonymous users (no __session cookie)" do
    test "sets cache-control header to allow CDN caching" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=43200, max-age=0, must-revalidate"
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
  end

  describe "edge cases" do
    test "empty __session cookie is treated as anonymous" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("__session", "")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=43200, max-age=0, must-revalidate"
             ]
    end

    test "other cookies without __session is treated as anonymous" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("other_cookie", "some-value")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "public, s-maxage=43200, max-age=0, must-revalidate"
             ]
    end
  end
end
