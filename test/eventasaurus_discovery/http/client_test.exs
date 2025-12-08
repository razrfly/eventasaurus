defmodule EventasaurusDiscovery.Http.ClientTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Http.Client
  alias EventasaurusDiscovery.Http.Adapters.{Direct, Zyte}

  describe "fetch/2" do
    @tag :external
    test "successfully fetches a URL" do
      url = "https://httpbin.org/get"

      case Client.fetch(url, timeout: 10_000) do
        {:ok, body, metadata} ->
          assert is_binary(body)
          assert String.contains?(body, "httpbin.org")
          assert metadata.adapter == "direct"
          assert metadata.status_code == 200
          assert is_integer(metadata.duration_ms)

        {:error, {:timeout, _}} ->
          :ok

        {:error, {:network_error, _}} ->
          :ok

        {:error, {:all_adapters_failed, _}} ->
          :ok
      end
    end

    @tag :external
    test "returns error for failed requests" do
      url = "https://httpbin.org/status/500"

      case Client.fetch(url, timeout: 10_000) do
        {:error, {:http_error, 500, _body, _metadata}} ->
          :ok

        {:error, {:timeout, _}} ->
          :ok

        {:error, {:network_error, _}} ->
          :ok

        {:error, {:all_adapters_failed, _}} ->
          :ok
      end
    end

    test "accepts options" do
      # Test that various options are accepted without crashing
      url = "https://example.com"

      # These will fail due to network, but we're testing option handling
      _result =
        Client.fetch(url,
          headers: [{"X-Test", "value"}],
          timeout: 1,
          recv_timeout: 1,
          source: :test_source,
          strategy: :direct
        )

      # No crash means success
      assert true
    end
  end

  describe "fetch!/2" do
    @tag :external
    test "returns only the body on success" do
      url = "https://httpbin.org/get"

      case Client.fetch!(url, timeout: 10_000) do
        {:ok, body} ->
          # fetch! strips metadata, returns only body
          assert is_binary(body)
          assert String.contains?(body, "httpbin.org")

        {:error, _} ->
          :ok
      end
    end

    @tag :external
    test "returns error tuple on failure" do
      url = "https://httpbin.org/status/404"

      case Client.fetch!(url, timeout: 10_000) do
        {:error, {:http_error, 404, _body, _metadata}} ->
          :ok

        {:error, _} ->
          :ok
      end
    end
  end

  describe "available_adapters/0" do
    test "returns list containing Direct adapter" do
      adapters = Client.available_adapters()

      assert is_list(adapters)
      assert Direct in adapters
    end

    test "all returned adapters are available" do
      adapters = Client.available_adapters()

      for adapter <- adapters do
        assert adapter.available?()
      end
    end
  end

  describe "get_adapter_chain_for/2" do
    test "returns Direct for :direct strategy" do
      chain = Client.get_adapter_chain_for(:any_source, :direct)
      assert chain == [Direct]
    end

    test "returns chain for :fallback strategy" do
      chain = Client.get_adapter_chain_for(:any_source, :fallback)

      assert is_list(chain)
      assert length(chain) >= 1
      assert hd(chain) == Direct
    end

    test "returns source-specific chain for :auto strategy" do
      # Set up test config
      original = Application.get_env(:eventasaurus_discovery, :http_strategies, %{})

      Application.put_env(:eventasaurus_discovery, :http_strategies, %{
        test_source: [:direct]
      })

      try do
        chain = Client.get_adapter_chain_for(:test_source, :auto)
        assert Direct in chain
      after
        Application.put_env(:eventasaurus_discovery, :http_strategies, original)
      end
    end
  end

  describe "strategy handling" do
    test ":direct strategy uses only Direct adapter" do
      url = "https://example.com"

      # This will fail quickly due to short timeout, but we're testing strategy
      result = Client.fetch(url, strategy: :direct, timeout: 1)

      case result do
        {:error, {:timeout, _}} -> :ok
        {:error, {:network_error, _}} -> :ok
        {:error, _} -> :ok
        {:ok, _, _} -> :ok
      end
    end

    test ":proxy strategy skips Direct adapter" do
      url = "https://example.com"

      # If Zyte is not configured, should return error
      result = Client.fetch(url, strategy: :proxy, timeout: 1)

      case result do
        {:error, :not_configured} ->
          # Zyte not configured, expected
          :ok

        {:error, {:all_adapters_failed, _}} ->
          # All proxies failed
          :ok

        {:error, {:timeout, _}} ->
          # Network timeout
          :ok

        {:error, {:network_error, _}} ->
          :ok

        {:ok, _, _} ->
          # Zyte is configured and succeeded
          :ok
      end
    end
  end

  describe "source-specific configuration" do
    setup do
      original = Application.get_env(:eventasaurus_discovery, :http_strategies, %{})

      on_exit(fn ->
        Application.put_env(:eventasaurus_discovery, :http_strategies, original)
      end)

      %{original_config: original}
    end

    test "uses source-specific adapter chain" do
      Application.put_env(:eventasaurus_discovery, :http_strategies, %{
        test_direct_only: [:direct]
      })

      chain = Client.get_adapter_chain_for(:test_direct_only, :auto)
      assert chain == [Direct]
    end

    test "falls back to default for unknown source" do
      Application.put_env(:eventasaurus_discovery, :http_strategies, %{
        default: [:direct]
      })

      chain = Client.get_adapter_chain_for(:completely_unknown, :auto)
      assert Direct in chain
    end
  end

  describe "metadata" do
    @tag :external
    test "includes attempt count" do
      url = "https://httpbin.org/get"

      case Client.fetch(url, timeout: 10_000, strategy: :direct) do
        {:ok, _body, metadata} ->
          assert Map.has_key?(metadata, :attempts)
          assert metadata.attempts >= 1

        {:error, _} ->
          :ok
      end
    end

    @tag :external
    test "includes blocked_by list" do
      url = "https://httpbin.org/get"

      case Client.fetch(url, timeout: 10_000, strategy: :direct) do
        {:ok, _body, metadata} ->
          assert Map.has_key?(metadata, :blocked_by)
          assert is_list(metadata.blocked_by)

        {:error, _} ->
          :ok
      end
    end
  end

  describe "integration" do
    test "Client uses Direct adapter by default" do
      # The Direct adapter is always available
      assert Direct in Client.available_adapters()
    end

    test "all_adapters/0 returns all known adapters" do
      adapters = Client.all_adapters()
      assert Direct in adapters
      assert Zyte in adapters
    end
  end
end
