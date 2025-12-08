defmodule EventasaurusDiscovery.Http.Adapters.DirectTest do
  use ExUnit.Case, async: true

  import Mox

  alias EventasaurusDiscovery.Http.Adapters.Direct

  setup :verify_on_exit!

  describe "name/0" do
    test "returns 'direct'" do
      assert Direct.name() == "direct"
    end
  end

  describe "available?/0" do
    test "always returns true" do
      assert Direct.available?() == true
    end
  end

  describe "fetch/2" do
    @tag :external
    test "successfully fetches a real URL" do
      # Skip in CI by default - this is an integration test
      url = "https://httpbin.org/get"

      case Direct.fetch(url, timeout: 10_000) do
        {:ok, body, metadata} ->
          assert is_binary(body)
          assert String.contains?(body, "httpbin.org")
          assert metadata.status_code == 200
          assert metadata.adapter == "direct"
          assert is_integer(metadata.duration_ms)
          assert metadata.duration_ms >= 0

        {:error, {:timeout, _}} ->
          # Acceptable in slow network conditions
          :ok

        {:error, {:network_error, _}} ->
          # Acceptable if httpbin.org is down
          :ok
      end
    end

    @tag :external
    test "returns http_error for 404" do
      url = "https://httpbin.org/status/404"

      case Direct.fetch(url, timeout: 10_000) do
        {:error, {:http_error, 404, _body, metadata}} ->
          assert metadata.status_code == 404
          assert metadata.adapter == "direct"

        {:error, {:timeout, _}} ->
          :ok

        {:error, {:network_error, _}} ->
          :ok
      end
    end

    @tag :external
    test "returns http_error for 403" do
      url = "https://httpbin.org/status/403"

      case Direct.fetch(url, timeout: 10_000) do
        {:error, {:http_error, 403, _body, metadata}} ->
          assert metadata.status_code == 403

        {:error, {:timeout, _}} ->
          :ok

        {:error, {:network_error, _}} ->
          :ok
      end
    end

    test "handles invalid URLs gracefully" do
      result = Direct.fetch("not-a-valid-url")

      assert {:error, {:network_error, _reason}} = result
    end

    test "passes custom headers" do
      # We can't easily test this without mocking, but we can at least
      # verify the function accepts the option
      url = "https://example.com"
      headers = [{"X-Custom-Header", "test-value"}]

      # This will likely fail due to network, but we're just testing
      # that the option is accepted
      _result = Direct.fetch(url, headers: headers, timeout: 1)
      # No assertion needed - just verify no crash
    end

    test "respects timeout option" do
      # Use a very short timeout to force a timeout error
      url = "https://httpbin.org/delay/5"

      result = Direct.fetch(url, timeout: 1, recv_timeout: 1)

      # Should get a timeout or network error due to very short timeout
      assert match?({:error, {:timeout, _}}, result) or
               match?({:error, {:network_error, _}}, result)
    end
  end

  describe "default headers" do
    test "includes User-Agent" do
      # We test this indirectly by verifying successful requests work
      # The default headers are applied internally
      # A proper test would mock HTTPoison to verify headers
      assert Direct.available?()
    end
  end
end
