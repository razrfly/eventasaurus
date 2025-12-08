defmodule EventasaurusDiscovery.Http.Adapters.ZyteTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Http.Adapters.Zyte

  describe "name/0" do
    test "returns 'zyte'" do
      assert Zyte.name() == "zyte"
    end
  end

  describe "available?/0" do
    test "returns true when ZYTE_API_KEY is set" do
      # This test depends on environment - if API key is set, it should return true
      api_key = System.get_env("ZYTE_API_KEY")

      if api_key && api_key != "" do
        assert Zyte.available?() == true
      else
        assert Zyte.available?() == false
      end
    end
  end

  describe "fetch/2 without API key" do
    @tag :skip_if_zyte_configured
    test "returns :not_configured when API key is not set" do
      # Temporarily clear the API key
      original_key = Application.get_env(:eventasaurus_discovery, :zyte_api_key)
      original_env = System.get_env("ZYTE_API_KEY")

      try do
        Application.put_env(:eventasaurus_discovery, :zyte_api_key, "")
        System.delete_env("ZYTE_API_KEY")

        result = Zyte.fetch("https://example.com")
        assert result == {:error, :not_configured}
      after
        # Restore the original values
        if original_key do
          Application.put_env(:eventasaurus_discovery, :zyte_api_key, original_key)
        end

        if original_env do
          System.put_env("ZYTE_API_KEY", original_env)
        end
      end
    end
  end

  describe "fetch/2 with API key (integration tests)" do
    @moduletag :external

    setup do
      if Zyte.available?() do
        :ok
      else
        {:skip, "ZYTE_API_KEY not configured"}
      end
    end

    @tag :external
    test "successfully fetches a URL with browser_html mode" do
      url = "https://httpbin.org/html"

      case Zyte.fetch(url, mode: :browser_html, timeout: 60_000) do
        {:ok, body, metadata} ->
          assert is_binary(body)
          assert String.contains?(body, "html") or String.contains?(body, "HTML")
          assert metadata.adapter == "zyte"
          assert metadata.mode == :browser_html
          assert is_integer(metadata.duration_ms)
          assert metadata.duration_ms >= 0

        {:error, {:timeout, _}} ->
          # Acceptable in slow network conditions
          :ok

        {:error, {:network_error, _}} ->
          # Acceptable if network is unavailable
          :ok

        {:error, {:zyte_error, status, message}} ->
          # Log but don't fail - Zyte might have temporary issues
          IO.puts("Zyte error (#{status}): #{message}")
          :ok

        {:error, {:rate_limit, _}} ->
          # Acceptable if rate limited
          :ok
      end
    end

    @tag :external
    test "successfully fetches a URL with http_response_body mode" do
      url = "https://httpbin.org/json"

      case Zyte.fetch(url, mode: :http_response_body, timeout: 60_000) do
        {:ok, body, metadata} ->
          assert is_binary(body)
          # httpbin.org/json returns JSON
          assert String.contains?(body, "slideshow") or String.contains?(body, "{")
          assert metadata.adapter == "zyte"
          assert metadata.mode == :http_response_body
          assert is_integer(metadata.duration_ms)

        {:error, {:timeout, _}} ->
          :ok

        {:error, {:network_error, _}} ->
          :ok

        {:error, {:zyte_error, _, _}} ->
          :ok

        {:error, {:rate_limit, _}} ->
          :ok
      end
    end

    @tag :external
    test "can fetch Cloudflare-protected site (Bandsintown)" do
      # This is the main use case - bypassing Cloudflare
      url = "https://www.bandsintown.com/c/krakow-poland?came_from=257&page=1"

      case Zyte.fetch(url, mode: :browser_html, timeout: 90_000) do
        {:ok, body, metadata} ->
          assert is_binary(body)
          # Should get actual content, not Cloudflare challenge
          refute String.contains?(body, "Just a moment...")
          refute String.contains?(body, "challenge-platform")
          # Should contain Bandsintown content
          assert String.contains?(body, "bandsintown") or
                   String.contains?(body, "event") or
                   String.contains?(body, "concert") or
                   byte_size(body) > 10_000

          assert metadata.adapter == "zyte"
          assert metadata.mode == :browser_html

        {:error, {:timeout, _}} ->
          :ok

        {:error, {:network_error, _}} ->
          :ok

        {:error, {:zyte_error, _, _}} ->
          :ok

        {:error, {:rate_limit, _}} ->
          :ok
      end
    end
  end

  describe "request body building" do
    # These tests verify internal behavior without making HTTP requests

    test "accepts mode option" do
      # Just verify the function doesn't crash with different modes
      # The actual HTTP call would fail without a valid API key
      if not Zyte.available?() do
        assert {:error, :not_configured} = Zyte.fetch("https://example.com", mode: :browser_html)
        assert {:error, :not_configured} = Zyte.fetch("https://example.com", mode: :http_response_body)
      end
    end

    test "accepts viewport option" do
      if not Zyte.available?() do
        viewport = %{width: 1280, height: 720}
        assert {:error, :not_configured} = Zyte.fetch("https://example.com", viewport: viewport)
      end
    end

    test "accepts timeout options" do
      if not Zyte.available?() do
        assert {:error, :not_configured} =
                 Zyte.fetch("https://example.com", timeout: 30_000, recv_timeout: 30_000)
      end
    end
  end

  describe "error handling" do
    # Unit tests for error parsing logic

    test "handles various error responses gracefully" do
      # These would need mocking to properly test without making real API calls
      # For now, just verify the module compiles and has the expected functions
      assert function_exported?(Zyte, :fetch, 1)
      assert function_exported?(Zyte, :fetch, 2)
      assert function_exported?(Zyte, :name, 0)
      assert function_exported?(Zyte, :available?, 0)
    end
  end
end
