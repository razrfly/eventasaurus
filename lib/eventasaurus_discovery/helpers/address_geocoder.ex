defmodule EventasaurusDiscovery.Helpers.AddressGeocoder do
  @moduledoc """
  Forward geocoding: convert full address strings to city names and coordinates.

  ## Multi-Provider Strategy (Phase 2 Complete)

  Uses the Orchestrator to try multiple geocoding providers in priority order:

  **Free Providers** (tried first):
  1. Mapbox (100K/month free, high quality, global coverage)
  2. HERE (250K/month free, high quality, generous rate limits)
  3. Geoapify (90K/month free, good quality)
  4. LocationIQ (150K/month free, OSM-based)
  5. OpenStreetMap (free, 1 req/sec limit)
  6. Photon (unlimited free, OSM-based, community service)

  **Paid Providers** (disabled by default, last resort):
  97. Google Maps ($0.005/call, DISABLED)
  99. Google Places ($0.034/call, DISABLED)

  The Orchestrator handles fallback logic and tracks which providers were attempted.

  ## Legacy Support

  The `geocode_address/1` function is maintained for backward compatibility.
  Use `geocode_address_with_metadata/1` for full provider tracking metadata.
  """

  require Logger
  alias EventasaurusDiscovery.Geocoding.Orchestrator

  @doc """
  Geocode a full address string to extract city name, country, and coordinates.

  **Legacy function** - maintained for backward compatibility.
  Uses the multi-provider Orchestrator internally.

  ## Examples

      iex> geocode_address("123 Main St, London, UK")
      {:ok, {"London", "United Kingdom", {51.5074, -0.1278}}}

      iex> geocode_address("invalid address")
      {:error, :geocoding_failed}
  """
  @spec geocode_address(String.t()) ::
          {:ok, {city :: String.t(), country :: String.t(), coordinates :: {float(), float()}}}
          | {:error, atom()}
  def geocode_address(address) when is_binary(address) do
    case geocode_address_with_metadata(address) do
      {:ok, %{city: city, country: country, latitude: lat, longitude: lng}} ->
        {:ok, {city, country, {lat, lng}}}

      {:error, _reason, _metadata} ->
        {:error, :geocoding_failed}
    end
  end

  def geocode_address(_), do: {:error, :invalid_address}

  @doc """
  Geocode an address using multi-provider orchestration with metadata tracking.

  Uses the Orchestrator to try multiple providers in priority order.
  Returns full metadata about which providers were attempted.

  ## Multi-Provider Fallback (Phase 2 Complete)

  **Free Providers** (tried first):
  1. Mapbox (100K/month free, high quality)
  2. HERE (250K/month free, high quality)
  3. Geoapify (90K/month free, good quality)
  4. LocationIQ (150K/month free, OSM-based)
  5. OpenStreetMap (free, 1 req/sec limit)
  6. Photon (unlimited free, OSM-based)

  **Paid Providers** (disabled by default):
  97. Google Maps ($0.005/call)
  99. Google Places ($0.034/call)

  ## Parameters
  - `address` - Full address string to geocode

  ## Returns
  - `{:ok, result}` - Success with coordinates and metadata
  - `{:error, reason, metadata}` - All providers failed with attempt history

  ## Examples

      iex> geocode_address_with_metadata("123 Main St, London, UK")
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

      iex> geocode_address_with_metadata("invalid address")
      {:error, :all_failed, %{
        attempted_providers: ["mapbox", "here", "geoapify", "locationiq", "openstreetmap", "photon"],
        attempts: 6,
        all_failed: true
      }}
  """
  @spec geocode_address_with_metadata(String.t()) ::
          {:ok,
           %{
             city: String.t(),
             country: String.t(),
             latitude: float(),
             longitude: float(),
             geocoding_metadata: map()
           }}
          | {:error, atom(), map()}
  def geocode_address_with_metadata(address) when is_binary(address) do
    case Orchestrator.geocode(address) do
      {:ok, result} ->
        # Success! Orchestrator already included geocoding_metadata
        {:ok, result}

      {:error, reason, metadata} ->
        # All providers failed
        Logger.warning(
          "⚠️ All geocoding providers failed for: #{address}. " <>
            "Attempted: #{inspect(Map.get(metadata, :attempted_providers, []))}"
        )

        {:error, reason, metadata}
    end
  end

  def geocode_address_with_metadata(_) do
    {:error, :invalid_address, %{attempted_providers: []}}
  end
end
