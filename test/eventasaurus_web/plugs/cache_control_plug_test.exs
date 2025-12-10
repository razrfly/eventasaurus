defmodule EventasaurusWeb.Plugs.CacheControlPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias EventasaurusWeb.Plugs.CacheControlPlug

  describe "call/2" do
    test "sets cache-control header to prevent caching" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "cache-control") == [
               "private, no-cache, no-store, must-revalidate"
             ]
    end

    test "sets vary header to Cookie" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "vary") == ["Cookie"]
    end

    test "sets pragma header to no-cache for HTTP/1.0 compatibility" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "pragma") == ["no-cache"]
    end

    test "sets expires header to 0" do
      conn =
        :get
        |> conn("/")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "expires") == ["0"]
    end

    test "merges Cookie with existing vary header" do
      conn =
        :get
        |> conn("/")
        |> put_resp_header("vary", "Accept-Encoding")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "vary") == ["Accept-Encoding, Cookie"]
    end

    test "does not duplicate Cookie in vary header" do
      conn =
        :get
        |> conn("/")
        |> put_resp_header("vary", "Accept-Encoding, Cookie")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "vary") == ["Accept-Encoding, Cookie"]
    end

    test "handles vary header with only Cookie" do
      conn =
        :get
        |> conn("/")
        |> put_resp_header("vary", "Cookie")
        |> CacheControlPlug.call([])

      assert get_resp_header(conn, "vary") == ["Cookie"]
    end
  end
end
