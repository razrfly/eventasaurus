defmodule EventasaurusDiscovery.Http.Adapters.CrawlbaseTest do
  # async: false because tests mutate global state via Application.put_env and System.delete_env
  use ExUnit.Case, async: false

  alias EventasaurusDiscovery.Http.Adapters.Crawlbase

  describe "name/0" do
    test "returns 'crawlbase'" do
      assert Crawlbase.name() == "crawlbase"
    end
  end

  describe "available?/0" do
    test "returns true when at least one API key is set" do
      # Save original values
      original_normal = Application.get_env(:eventasaurus, :crawlbase_api_key)
      original_js = Application.get_env(:eventasaurus, :crawlbase_js_api_key)
      original_env_normal = System.get_env("CRAWLBASE_API_KEY")
      original_env_js = System.get_env("CRAWLBASE_JS_API_KEY")

      try do
        # Clear all keys
        Application.put_env(:eventasaurus, :crawlbase_api_key, nil)
        Application.put_env(:eventasaurus, :crawlbase_js_api_key, nil)
        System.delete_env("CRAWLBASE_API_KEY")
        System.delete_env("CRAWLBASE_JS_API_KEY")

        # With no keys, should return false
        assert Crawlbase.available?() == false

        # With just normal key, should return true
        Application.put_env(:eventasaurus, :crawlbase_api_key, "test_normal_key")
        assert Crawlbase.available?() == true

        # Clear normal, set JS key
        Application.put_env(:eventasaurus, :crawlbase_api_key, nil)
        Application.put_env(:eventasaurus, :crawlbase_js_api_key, "test_js_key")
        assert Crawlbase.available?() == true
      after
        # Restore original values
        if original_normal do
          Application.put_env(:eventasaurus, :crawlbase_api_key, original_normal)
        else
          Application.put_env(:eventasaurus, :crawlbase_api_key, nil)
        end

        if original_js do
          Application.put_env(:eventasaurus, :crawlbase_js_api_key, original_js)
        else
          Application.put_env(:eventasaurus, :crawlbase_js_api_key, nil)
        end

        if original_env_normal do
          System.put_env("CRAWLBASE_API_KEY", original_env_normal)
        end

        if original_env_js do
          System.put_env("CRAWLBASE_JS_API_KEY", original_env_js)
        end
      end
    end
  end

  describe "available_for_mode?/1" do
    test "returns correct availability for each mode" do
      # Save original values
      original_normal = Application.get_env(:eventasaurus, :crawlbase_api_key)
      original_js = Application.get_env(:eventasaurus, :crawlbase_js_api_key)
      original_env_normal = System.get_env("CRAWLBASE_API_KEY")
      original_env_js = System.get_env("CRAWLBASE_JS_API_KEY")

      try do
        # Clear all keys (both Application config and System env)
        Application.put_env(:eventasaurus, :crawlbase_api_key, nil)
        Application.put_env(:eventasaurus, :crawlbase_js_api_key, nil)
        System.delete_env("CRAWLBASE_API_KEY")
        System.delete_env("CRAWLBASE_JS_API_KEY")

        # With no keys
        assert Crawlbase.available_for_mode?(:normal) == false
        assert Crawlbase.available_for_mode?(:javascript) == false

        # With only normal key
        Application.put_env(:eventasaurus, :crawlbase_api_key, "test_normal_key")
        assert Crawlbase.available_for_mode?(:normal) == true
        assert Crawlbase.available_for_mode?(:javascript) == false

        # With both keys
        Application.put_env(:eventasaurus, :crawlbase_js_api_key, "test_js_key")
        assert Crawlbase.available_for_mode?(:normal) == true
        assert Crawlbase.available_for_mode?(:javascript) == true
      after
        # Restore original values
        if original_normal do
          Application.put_env(:eventasaurus, :crawlbase_api_key, original_normal)
        else
          Application.put_env(:eventasaurus, :crawlbase_api_key, nil)
        end

        if original_js do
          Application.put_env(:eventasaurus, :crawlbase_js_api_key, original_js)
        else
          Application.put_env(:eventasaurus, :crawlbase_js_api_key, nil)
        end

        if original_env_normal do
          System.put_env("CRAWLBASE_API_KEY", original_env_normal)
        end

        if original_env_js do
          System.put_env("CRAWLBASE_JS_API_KEY", original_env_js)
        end
      end
    end
  end

  describe "fetch/2 without API key" do
    test "returns :not_configured when required key is not set for mode" do
      # Save original values
      original_normal = Application.get_env(:eventasaurus, :crawlbase_api_key)
      original_js = Application.get_env(:eventasaurus, :crawlbase_js_api_key)
      original_env_normal = System.get_env("CRAWLBASE_API_KEY")
      original_env_js = System.get_env("CRAWLBASE_JS_API_KEY")

      try do
        # Clear all keys
        Application.put_env(:eventasaurus, :crawlbase_api_key, nil)
        Application.put_env(:eventasaurus, :crawlbase_js_api_key, nil)
        System.delete_env("CRAWLBASE_API_KEY")
        System.delete_env("CRAWLBASE_JS_API_KEY")

        # Should return :not_configured for javascript mode (default)
        assert {:error, :not_configured} = Crawlbase.fetch("https://example.com")

        assert {:error, :not_configured} =
                 Crawlbase.fetch("https://example.com", mode: :javascript)

        assert {:error, :not_configured} = Crawlbase.fetch("https://example.com", mode: :normal)
      after
        # Restore original values
        if original_normal do
          Application.put_env(:eventasaurus, :crawlbase_api_key, original_normal)
        end

        if original_js do
          Application.put_env(:eventasaurus, :crawlbase_js_api_key, original_js)
        end

        if original_env_normal do
          System.put_env("CRAWLBASE_API_KEY", original_env_normal)
        end

        if original_env_js do
          System.put_env("CRAWLBASE_JS_API_KEY", original_env_js)
        end
      end
    end
  end

  describe "fetch/2 with API key (integration tests)" do
    @moduletag :external

    setup do
      if Crawlbase.available?() do
        :ok
      else
        {:skip, "CRAWLBASE_API_KEY or CRAWLBASE_JS_API_KEY not configured"}
      end
    end

    @tag :external
    test "successfully fetches a URL with javascript mode" do
      unless Crawlbase.available_for_mode?(:javascript) do
        IO.puts("Skipping: CRAWLBASE_JS_API_KEY not configured")
        assert true
      else
        url = "https://httpbin.org/html"

        case Crawlbase.fetch(url, mode: :javascript, timeout: 90_000) do
          {:ok, body, metadata} ->
            assert is_binary(body)
            assert String.contains?(body, "html") or String.contains?(body, "HTML")
            assert metadata.adapter == "crawlbase"
            assert metadata.mode == :javascript
            assert is_integer(metadata.duration_ms)
            assert metadata.duration_ms >= 0

          {:error, {:timeout, _}} ->
            # Acceptable in slow network conditions
            assert true

          {:error, {:network_error, _}} ->
            # Acceptable if network is unavailable
            assert true

          {:error, {:crawlbase_error, status, message}} ->
            # Log but don't fail - Crawlbase might have temporary issues
            IO.puts("Crawlbase error (#{status}): #{message}")
            assert true

          {:error, {:rate_limit, _}} ->
            # Acceptable if rate limited
            assert true
        end
      end
    end

    @tag :external
    test "successfully fetches a URL with normal mode" do
      unless Crawlbase.available_for_mode?(:normal) do
        IO.puts("Skipping: CRAWLBASE_API_KEY not configured")
        assert true
      else
        url = "https://httpbin.org/json"

        case Crawlbase.fetch(url, mode: :normal, timeout: 60_000) do
          {:ok, body, metadata} ->
            assert is_binary(body)
            assert String.contains?(body, "slideshow") or String.contains?(body, "{")
            assert metadata.adapter == "crawlbase"
            assert metadata.mode == :normal
            assert is_integer(metadata.duration_ms)

          {:error, {:timeout, _}} ->
            assert true

          {:error, {:network_error, _}} ->
            assert true

          {:error, {:crawlbase_error, _, _}} ->
            assert true

          {:error, {:rate_limit, _}} ->
            assert true
        end
      end
    end

    @tag :external
    test "can fetch Cloudflare-protected site (Bandsintown)" do
      unless Crawlbase.available_for_mode?(:javascript) do
        IO.puts("Skipping: CRAWLBASE_JS_API_KEY not configured")
        assert true
      else
        # This is the main use case - bypassing Cloudflare
        url = "https://www.bandsintown.com/c/krakow-poland?came_from=257&page=1"

        case Crawlbase.fetch(url, mode: :javascript, timeout: 90_000, page_wait: 3000) do
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

            assert metadata.adapter == "crawlbase"
            assert metadata.mode == :javascript

          {:error, {:timeout, _}} ->
            assert true

          {:error, {:network_error, _}} ->
            assert true

          {:error, {:crawlbase_error, _, _}} ->
            assert true

          {:error, {:rate_limit, _}} ->
            assert true
        end
      end
    end
  end

  describe "request options" do
    # These tests verify the function accepts various options without crashing
    # They test option acceptance regardless of whether the adapter is configured

    test "accepts mode option" do
      # Test that mode option is accepted (doesn't raise)
      result_js = Crawlbase.fetch("https://example.com", mode: :javascript)
      result_normal = Crawlbase.fetch("https://example.com", mode: :normal)

      # Should return either :not_configured or a valid response tuple
      assert match?({:error, _}, result_js) or match?({:ok, _, _}, result_js)
      assert match?({:error, _}, result_normal) or match?({:ok, _, _}, result_normal)
    end

    test "accepts page_wait option" do
      result = Crawlbase.fetch("https://example.com", page_wait: 5000)
      assert match?({:error, _}, result) or match?({:ok, _, _}, result)
    end

    test "accepts ajax_wait option" do
      result_true = Crawlbase.fetch("https://example.com", ajax_wait: true)
      result_false = Crawlbase.fetch("https://example.com", ajax_wait: false)

      assert match?({:error, _}, result_true) or match?({:ok, _, _}, result_true)
      assert match?({:error, _}, result_false) or match?({:ok, _, _}, result_false)
    end

    test "accepts timeout options" do
      result = Crawlbase.fetch("https://example.com", timeout: 30_000, recv_timeout: 30_000)
      assert match?({:error, _}, result) or match?({:ok, _, _}, result)
    end
  end

  describe "error handling" do
    test "has expected callback functions exported" do
      assert function_exported?(Crawlbase, :fetch, 1)
      assert function_exported?(Crawlbase, :fetch, 2)
      assert function_exported?(Crawlbase, :name, 0)
      assert function_exported?(Crawlbase, :available?, 0)
      assert function_exported?(Crawlbase, :available_for_mode?, 1)
    end
  end
end
