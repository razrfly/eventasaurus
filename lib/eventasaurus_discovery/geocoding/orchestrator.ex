defmodule EventasaurusDiscovery.Geocoding.Orchestrator do
  @moduledoc """
  Orchestrates geocoding requests across multiple providers.

  Tries providers in configured priority order until one succeeds.
  Tracks which providers were attempted and stores metadata.

  ## Configuration

  Providers are now configured in the database via the `geocoding_providers` table.
  The admin UI allows dynamic reordering and enabling/disabling of providers.

  Configuration is read from `EventasaurusDiscovery.Geocoding.ProviderConfig`.

  ## Usage

      iex> Orchestrator.geocode("123 Main St, London, UK")
      {:ok, %{
        city: "London",
        country: "United Kingdom",
        latitude: 51.5074,
        longitude: -0.1278,
        geocoding_metadata: %{
          provider: "mapbox",
          attempted_providers: ["mapbox"],
          attempts: 1,
          geocoded_at: ~U[2025-01-12 10:30:00Z]
        }
      }}
  """

  require Logger
  alias EventasaurusDiscovery.Geocoding.{ProviderConfig, RateLimiter}

  @doc """
  Geocode an address using multiple providers in fallback order.

  Tries each enabled provider in priority order until one succeeds.
  Returns result with metadata about which providers were attempted.

  ## Parameters
  - `address` - Full address string to geocode

  ## Returns
  - `{:ok, result}` - Success with coordinates and metadata
  - `{:error, :all_failed, metadata}` - All providers failed
  """
  def geocode(address) when is_binary(address) do
    providers = get_enabled_providers()

    if Enum.empty?(providers) do
      Logger.error("❌ No geocoding providers enabled in configuration")
      {:error, :no_providers_configured, %{attempted_providers: []}}
    else
      Logger.info("🌍 Geocoding address: #{address} (#{length(providers)} providers available)")
      try_providers(address, providers, [])
    end
  end

  def geocode(_), do: {:error, :invalid_address, %{attempted_providers: []}}

  # Try providers recursively until one succeeds
  defp try_providers(_address, [], attempted) do
    # All providers failed
    Logger.error("❌ All #{length(attempted)} geocoding providers failed")

    metadata = %{
      attempted_providers: Enum.reverse(attempted),
      attempts: length(attempted),
      geocoded_at: DateTime.utc_now(),
      all_failed: true
    }

    {:error, :all_failed, metadata}
  end

  defp try_providers(address, [provider_module | rest], attempted) do
    provider_name = provider_module.name()
    Logger.debug("🔄 Trying provider: #{provider_name}")

    # Check rate limit BEFORE calling provider
    case RateLimiter.check_rate_limit(provider_name) do
      :ok ->
        # Rate limit OK, proceed with geocoding
        call_provider(address, provider_module, provider_name, rest, attempted)

      {:error, :rate_limited, retry_after_ms} ->
        # Rate limited, wait and retry (blocking)
        Logger.warning(
          "⏱️ #{provider_name} rate limited, waiting #{retry_after_ms}ms before retry..."
        )

        Process.sleep(retry_after_ms)

        # Retry same provider after waiting
        try_providers(address, [provider_module | rest], attempted)
    end
  end

  # Separated out to reduce nesting
  defp call_provider(address, provider_module, provider_name, rest, attempted) do
    case provider_module.geocode(address) do
      {:ok, %{latitude: lat, longitude: lng} = result}
      when is_float(lat) and is_float(lng) ->
        # Success!
        Logger.info("✅ Geocoded via #{provider_name}: #{lat}, #{lng}")

        metadata = %{
          provider: provider_name,
          attempted_providers: Enum.reverse([provider_name | attempted]),
          attempts: length(attempted) + 1,
          geocoded_at: DateTime.utc_now(),
          place_id: Map.get(result, :place_id),
          raw_response: Map.get(result, :raw_response)
        }

        {:ok, Map.put(result, :geocoding_metadata, metadata)}

      {:error, reason} ->
        # Failed, try next provider
        Logger.warning("⚠️ Provider #{provider_name} failed: #{inspect(reason)}")
        try_providers(address, rest, [provider_name | attempted])

      other ->
        # Invalid response format
        Logger.warning(
          "⚠️ Provider #{provider_name} returned invalid format: #{inspect(other)}"
        )

        try_providers(address, rest, [provider_name | attempted])
    end
  end

  # Get enabled providers from database sorted by priority
  # Providers with equal priority are shuffled for random selection (useful for testing)
  defp get_enabled_providers do
    ProviderConfig.list_active_providers()
    |> Enum.map(fn {module, _opts} -> module end)
  end
end
