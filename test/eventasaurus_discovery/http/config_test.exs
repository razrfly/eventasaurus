defmodule EventasaurusDiscovery.Http.ConfigTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Http.Config
  alias EventasaurusDiscovery.Http.Adapters.{Direct, Zyte}

  describe "get_adapter_chain/1" do
    test "returns Direct adapter for unconfigured source" do
      # Unknown sources should fall back to Direct (always available)
      chain = Config.get_adapter_chain(:unknown_source_xyz)
      assert Direct in chain
    end

    test "returns at least Direct adapter when no adapters available" do
      chain = Config.get_adapter_chain(:some_source)
      assert length(chain) >= 1
      assert Direct in chain
    end

    test "filters out unavailable adapters" do
      # Zyte requires API key, so if not configured it won't be in the chain
      chain = Config.get_adapter_chain(:default)

      # Direct should always be available
      assert Direct in chain
    end
  end

  describe "get_adapter_chain_for_strategy/2" do
    test ":direct strategy returns only Direct adapter" do
      chain = Config.get_adapter_chain_for_strategy(:direct, :any_source)
      assert chain == [Direct]
    end

    test ":proxy strategy returns proxy adapters when available" do
      chain = Config.get_adapter_chain_for_strategy(:proxy, :any_source)

      # If Zyte is available, it should be in the chain
      # If not, falls back to Direct
      assert length(chain) >= 1
    end

    test ":fallback strategy returns Direct first, then proxies" do
      chain = Config.get_adapter_chain_for_strategy(:fallback, :any_source)

      assert length(chain) >= 1
      # Direct should be first
      assert hd(chain) == Direct
    end

    test ":auto strategy delegates to source config" do
      chain = Config.get_adapter_chain_for_strategy(:auto, :default)

      # Should behave same as get_adapter_chain
      assert chain == Config.get_adapter_chain(:default)
    end
  end

  describe "get_strategy/1" do
    test "returns default strategy for unconfigured source" do
      strategy = Config.get_strategy(:completely_unknown_source)

      # Should return a valid adapter list
      assert is_list(strategy)
      assert length(strategy) >= 1
    end

    test "returns configured strategy when set" do
      # Set up a test config
      original = Application.get_env(:eventasaurus_discovery, :http_strategies, %{})

      Application.put_env(:eventasaurus_discovery, :http_strategies, %{
        test_source: [:zyte]
      })

      try do
        strategy = Config.get_strategy(:test_source)
        assert strategy == [:zyte]
      after
        Application.put_env(:eventasaurus_discovery, :http_strategies, original)
      end
    end
  end

  describe "get_all_strategies/0" do
    test "returns a map" do
      strategies = Config.get_all_strategies()
      assert is_map(strategies)
    end

    test "handles keyword list config" do
      original = Application.get_env(:eventasaurus_discovery, :http_strategies, %{})

      Application.put_env(:eventasaurus_discovery, :http_strategies, [
        {:default, [:direct]},
        {:test_source, [:zyte]}
      ])

      try do
        strategies = Config.get_all_strategies()
        assert is_map(strategies)
        assert strategies[:test_source] == [:zyte]
      after
        Application.put_env(:eventasaurus_discovery, :http_strategies, original)
      end
    end
  end

  describe "has_blocking_protection?/1" do
    test "returns false for direct-only source" do
      original = Application.get_env(:eventasaurus_discovery, :http_strategies, %{})

      Application.put_env(:eventasaurus_discovery, :http_strategies, %{
        direct_only: [:direct]
      })

      try do
        refute Config.has_blocking_protection?(:direct_only)
      after
        Application.put_env(:eventasaurus_discovery, :http_strategies, original)
      end
    end

    test "returns true when proxy is in chain (if available)" do
      original = Application.get_env(:eventasaurus_discovery, :http_strategies, %{})

      Application.put_env(:eventasaurus_discovery, :http_strategies, %{
        with_proxy: [:direct, :zyte]
      })

      try do
        # Only true if Zyte is available
        if Zyte.available?() do
          assert Config.has_blocking_protection?(:with_proxy)
        else
          # If Zyte not configured, only Direct is in chain
          refute Config.has_blocking_protection?(:with_proxy)
        end
      after
        Application.put_env(:eventasaurus_discovery, :http_strategies, original)
      end
    end
  end

  describe "blocking_detection_enabled?/1" do
    test "returns false for single-adapter chain" do
      original = Application.get_env(:eventasaurus_discovery, :http_strategies, %{})

      Application.put_env(:eventasaurus_discovery, :http_strategies, %{
        single: [:direct]
      })

      try do
        refute Config.blocking_detection_enabled?(:single)
      after
        Application.put_env(:eventasaurus_discovery, :http_strategies, original)
      end
    end

    test "returns true for multi-adapter chain" do
      original = Application.get_env(:eventasaurus_discovery, :http_strategies, %{})

      Application.put_env(:eventasaurus_discovery, :http_strategies, %{
        multi: [:direct, :zyte]
      })

      try do
        # Only true if we have multiple available adapters
        chain = Config.get_adapter_chain(:multi)

        if length(chain) > 1 do
          assert Config.blocking_detection_enabled?(:multi)
        else
          refute Config.blocking_detection_enabled?(:multi)
        end
      after
        Application.put_env(:eventasaurus_discovery, :http_strategies, original)
      end
    end
  end

  describe "configured_sources/0" do
    test "returns list of source atoms" do
      sources = Config.configured_sources()
      assert is_list(sources)
      assert Enum.all?(sources, &is_atom/1)
    end
  end

  describe "available_adapters/0" do
    test "always includes Direct" do
      adapters = Config.available_adapters()
      assert Direct in adapters
    end

    test "only includes available adapters" do
      adapters = Config.available_adapters()
      assert Enum.all?(adapters, & &1.available?())
    end
  end

  describe "all_adapters/0" do
    test "returns all known adapters" do
      adapters = Config.all_adapters()
      assert Direct in adapters
      assert Zyte in adapters
    end
  end
end
