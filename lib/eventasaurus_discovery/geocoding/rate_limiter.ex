defmodule EventasaurusDiscovery.Geocoding.RateLimiter do
  @moduledoc """
  Rate limiting for geocoding providers using Hammer.

  Enforces provider-specific rate limits read from database configuration.
  Uses Hammer backend configured in config.exs (ETS-based, global across all processes).

  ## Usage

      # Check if request can proceed (non-blocking)
      case RateLimiter.check_rate_limit("openstreetmap") do
        :ok ->
          # Make request
        {:error, :rate_limited, retry_after_ms} ->
          # Handle rate limit
      end

      # Wait for rate limit to clear (blocking)
      RateLimiter.await_rate_limit("openstreetmap")
      # Make request

  ## Rate Limit Configuration

  Rate limits are stored in provider metadata:
  ```json
  {
    "rate_limits": {
      "per_second": 1,
      "per_minute": 60,
      "per_hour": 3600
    }
  }
  ```

  ## Hammer Integration

  Uses Hammer v7 with ETS backend (configured in config.exs).
  - Bucket key format: `"geocoding:{provider_name}"`
  - Scale: 1000ms (1 second) for per_second limits
  - Automatically expires buckets after window

  ## Multi-Node Support

  Hammer ETS backend is per-node. For true distributed rate limiting across
  multiple nodes, consider upgrading to Hammer Redis backend.
  """

  use Hammer, backend: :ets

  require Logger
  alias EventasaurusDiscovery.Geocoding.ProviderConfig

  @doc """
  Check if a geocoding request can proceed for the given provider.

  Returns `:ok` if allowed, or `{:error, :rate_limited, retry_after_ms}` if rate limited.

  ## Examples

      iex> RateLimiter.check_rate_limit("mapbox")
      :ok

      iex> RateLimiter.check_rate_limit("openstreetmap")
      {:error, :rate_limited, 850}
  """
  def check_rate_limit(provider_name) when is_binary(provider_name) do
    case ProviderConfig.get_rate_limit(provider_name) do
      nil ->
        # No rate limit configured, allow request
        :ok

      %{"per_second" => limit} when is_integer(limit) and limit > 0 ->
        check_with_hammer(provider_name, limit)

      %{per_second: limit} when is_integer(limit) and limit > 0 ->
        check_with_hammer(provider_name, limit)

      _ ->
        # Invalid or missing rate limit config, allow request
        Logger.warning(
          "Invalid rate limit configuration for #{provider_name}, allowing request"
        )

        :ok
    end
  end

  @doc """
  Wait if needed to respect rate limits, then proceed.

  Blocks until rate limit allows request to proceed.
  Use this for synchronous geocoding in scrapers.

  ## Examples

      iex> RateLimiter.await_rate_limit("openstreetmap")
      :ok
  """
  def await_rate_limit(provider_name) when is_binary(provider_name) do
    case check_rate_limit(provider_name) do
      :ok ->
        :ok

      {:error, :rate_limited, retry_after_ms} ->
        Logger.debug("⏳ Waiting #{retry_after_ms}ms for #{provider_name} rate limit...")
        Process.sleep(retry_after_ms)
        # Recursive retry after waiting
        await_rate_limit(provider_name)
    end
  end

  @doc """
  Get rate limit information for a provider without checking.

  Returns the rate limit configuration or nil.

  ## Examples

      iex> RateLimiter.get_limit("openstreetmap")
      %{per_second: 1, per_minute: 60, per_hour: 3600}
  """
  def get_limit(provider_name) when is_binary(provider_name) do
    ProviderConfig.get_rate_limit(provider_name)
  end

  # Private functions

  defp check_with_hammer(provider_name, limit) do
    # Use Hammer to enforce rate limit
    # Bucket key: "geocoding:provider_name"
    # Scale: 1000ms (1 second)
    # Limit: configured per_second value
    bucket_key = "geocoding:#{provider_name}"

    case hit(bucket_key, 1000, limit) do
      {:allow, _count} ->
        :ok

      {:deny, retry_after_ms} ->
        Logger.debug(
          "⏱️ Rate limit hit for #{provider_name}, retry after #{retry_after_ms}ms (limit: #{limit}/sec)"
        )

        {:error, :rate_limited, retry_after_ms}
    end
  end
end
