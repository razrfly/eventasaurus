defmodule EventasaurusDiscovery.Http.AdapterTest do
  @moduledoc """
  Tests for the HTTP Adapter behaviour and compliance verification.

  This module tests that all adapters properly implement the
  EventasaurusDiscovery.Http.Adapter behaviour.
  """
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Http.Adapter
  alias EventasaurusDiscovery.Http.Adapters.{Direct, Zyte}
  alias EventasaurusDiscovery.Http.Config

  @all_adapters [Direct, Zyte]

  describe "behaviour compliance" do
    test "all adapters implement the Adapter behaviour" do
      for adapter <- @all_adapters do
        # Check that each adapter module declares the behaviour
        behaviours = adapter.__info__(:attributes) |> Keyword.get(:behaviour, [])
        assert Adapter in behaviours,
               "#{inspect(adapter)} should implement Adapter behaviour"
      end
    end

    test "all adapters export name/0" do
      for adapter <- @all_adapters do
        assert function_exported?(adapter, :name, 0),
               "#{inspect(adapter)} should export name/0"
      end
    end

    test "all adapters export available?/0" do
      for adapter <- @all_adapters do
        assert function_exported?(adapter, :available?, 0),
               "#{inspect(adapter)} should export available?/0"
      end
    end

    test "all adapters export fetch/1 and fetch/2" do
      for adapter <- @all_adapters do
        assert function_exported?(adapter, :fetch, 1) or function_exported?(adapter, :fetch, 2),
               "#{inspect(adapter)} should export fetch/1 or fetch/2"
      end
    end
  end

  describe "name/0 contract" do
    test "all adapters return a non-empty string" do
      for adapter <- @all_adapters do
        name = adapter.name()
        assert is_binary(name), "#{inspect(adapter)}.name() should return a string"
        assert byte_size(name) > 0, "#{inspect(adapter)}.name() should return a non-empty string"
      end
    end

    test "adapter names are unique" do
      names = Enum.map(@all_adapters, & &1.name())
      assert length(names) == length(Enum.uniq(names)),
             "All adapters should have unique names, got: #{inspect(names)}"
    end

    test "adapter names are lowercase strings" do
      for adapter <- @all_adapters do
        name = adapter.name()
        assert name == String.downcase(name),
               "#{inspect(adapter)}.name() should be lowercase, got: #{name}"
      end
    end
  end

  describe "available?/0 contract" do
    test "all adapters return a boolean" do
      for adapter <- @all_adapters do
        result = adapter.available?()
        assert is_boolean(result),
               "#{inspect(adapter)}.available?() should return a boolean, got: #{inspect(result)}"
      end
    end

    test "Direct adapter is always available" do
      assert Direct.available?() == true
    end

    test "Zyte adapter availability depends on API key" do
      api_key = System.get_env("ZYTE_API_KEY")
      app_key = Application.get_env(:eventasaurus_discovery, :zyte_api_key)

      if (api_key && api_key != "") or (app_key && app_key != "") do
        assert Zyte.available?() == true
      else
        assert Zyte.available?() == false
      end
    end
  end

  describe "fetch/2 contract" do
    test "adapters handle invalid URLs gracefully" do
      for adapter <- Config.available_adapters() do
        result = adapter.fetch("not-a-valid-url", timeout: 1)

        # Should return an error, not crash
        case result do
          {:ok, _, _} -> :ok
          {:error, _} -> :ok
          other -> flunk("#{inspect(adapter)}.fetch() should return {:ok, _, _} or {:error, _}, got: #{inspect(other)}")
        end
      end
    end

    test "adapters accept options without crashing" do
      for adapter <- Config.available_adapters() do
        # These will likely fail due to network/timeout, but shouldn't crash
        _result = adapter.fetch("https://example.com",
          headers: [{"X-Test", "value"}],
          timeout: 1,
          recv_timeout: 1
        )

        # Just verify no crash - we're testing option handling
        assert true
      end
    end

    test "unavailable adapters return :not_configured error" do
      # Test Zyte when not configured
      original_app_key = Application.get_env(:eventasaurus_discovery, :zyte_api_key)
      original_env_key = System.get_env("ZYTE_API_KEY")

      try do
        Application.put_env(:eventasaurus_discovery, :zyte_api_key, "")
        System.delete_env("ZYTE_API_KEY")

        if not Zyte.available?() do
          result = Zyte.fetch("https://example.com")
          assert result == {:error, :not_configured}
        end
      after
        if original_app_key do
          Application.put_env(:eventasaurus_discovery, :zyte_api_key, original_app_key)
        end
        if original_env_key do
          System.put_env("ZYTE_API_KEY", original_env_key)
        end
      end
    end
  end

  describe "response metadata contract" do
    @tag :external
    test "successful responses include required metadata fields" do
      # Only test with Direct adapter (always available)
      url = "https://httpbin.org/get"

      case Direct.fetch(url, timeout: 10_000) do
        {:ok, body, metadata} ->
          assert is_binary(body)
          assert is_map(metadata)
          assert Map.has_key?(metadata, :status_code)
          assert Map.has_key?(metadata, :adapter)
          assert Map.has_key?(metadata, :duration_ms)
          assert is_integer(metadata.status_code)
          assert is_binary(metadata.adapter)
          assert is_integer(metadata.duration_ms)
          assert metadata.duration_ms >= 0

        {:error, {:timeout, _}} ->
          :ok

        {:error, {:network_error, _}} ->
          :ok
      end
    end
  end

  describe "error response patterns" do
    test "adapters use standard error tuples" do
      # Test with invalid URL to trigger error
      for adapter <- Config.available_adapters() do
        result = adapter.fetch("not-a-url", timeout: 1)

        case result do
          {:ok, _, _} ->
            :ok

          {:error, {:http_error, status, _body, _meta}} when is_integer(status) ->
            :ok

          {:error, {:timeout, _}} ->
            :ok

          {:error, {:network_error, _}} ->
            :ok

          {:error, :not_configured} ->
            :ok

          {:error, reason} when is_atom(reason) ->
            :ok

          {:error, {type, _}} when is_atom(type) ->
            :ok

          other ->
            flunk("#{inspect(adapter)}.fetch() returned unexpected pattern: #{inspect(other)}")
        end
      end
    end
  end

  describe "Config.all_adapters/0 coverage" do
    test "all registered adapters are tested" do
      registered = Config.all_adapters()
      tested = @all_adapters

      for adapter <- registered do
        assert adapter in tested,
               "#{inspect(adapter)} is registered but not tested. Add it to @all_adapters."
      end
    end
  end
end
