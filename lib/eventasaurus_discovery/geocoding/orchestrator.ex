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
        provider_ids: %{
          "mapbox" => "poi.123456789"
        },
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
  - `opts` - Keyword list of options
    - `:providers` - List of provider names to use instead of normal priority system.
      Used for reverse geocoding during backfill when we need specific provider IDs.
      Example: `providers: ["google_places"]`

  ## Returns
  - `{:ok, result}` - Success with coordinates and metadata
  - `{:error, :all_failed, metadata}` - All providers failed

  ## Special Use Case: Provider Override

  When `:providers` option is specified, the normal priority system is bypassed.
  This is used during venue backfill operations when we need provider-specific IDs
  (e.g., Google Places place_id) to fetch images from those providers.

  Note: This is NOT reverse geocoding (coordinates → address). The address is still
  required for geocoding. This option simply forces specific provider(s) to be used
  instead of following the normal priority system.

  ## Examples

      # Normal geocoding - uses priority system
      geocode("123 Main St, Portland, OR")

      # Provider override for backfill - collects IDs from all specified providers
      geocode("123 Main St, Portland, OR", providers: ["google_places", "foursquare"])
  """
  def geocode(address, opts \\ [])

  def geocode(address, opts) when is_binary(address) do
    provider_names = Keyword.get(opts, :providers)

    providers =
      case provider_names do
        nil ->
          get_enabled_providers()

        names when is_list(names) ->
          ProviderConfig.get_specific_providers(names)
          |> Enum.map(fn {module, _opts} -> module end)
      end

    if Enum.empty?(providers) do
      Logger.error("❌ No geocoding providers enabled in configuration")
      {:error, :no_providers_configured, %{attempted_providers: []}}
    else
      Logger.info("🌍 Geocoding address: #{address} (#{length(providers)} providers available)")

      # When specific providers are requested, collect IDs from ALL of them
      # This is used during backfill to get provider-specific IDs for image fetching
      case provider_names do
        nil -> try_providers(address, providers, [])
        _ -> try_all_providers(address, providers)
      end
    end
  end

  def geocode(_, _), do: {:error, :invalid_address, %{attempted_providers: []}}

  # Try ALL providers and collect provider IDs from each
  # Used when specific providers are requested (backfill scenario)
  defp try_all_providers(address, providers) do
    Logger.info("🔄 Collecting provider IDs from #{length(providers)} providers")

    result =
      Enum.reduce(
        providers,
        %{
          provider_ids: %{},
          attempted: [],
          first_success: nil,
          raw_responses: []
        },
        fn provider_module, acc ->
          provider_name = provider_module.name()
          Logger.debug("🔄 Trying provider: #{provider_name}")

          # Check rate limit BEFORE calling provider
          case RateLimiter.check_rate_limit(provider_name) do
            :ok ->
              call_provider_for_collection(address, provider_module, provider_name, acc)

            {:error, :rate_limited, retry_after_ms} ->
              Logger.warning("⏱️ #{provider_name} rate limited, waiting #{retry_after_ms}ms...")
              Process.sleep(retry_after_ms)
              # Retry after waiting
              call_provider_for_collection(address, provider_module, provider_name, acc)
          end
        end
      )

    # Build final response from collected data
    case result.first_success do
      {lat, lng, first_result} ->
        # Success! Use coordinates from first successful provider, but include ALL provider IDs
        Logger.info(
          "✅ Collected #{map_size(result.provider_ids)} provider IDs from #{length(result.attempted)} providers"
        )

        metadata = %{
          provider: first_result[:provider_name] || List.first(result.attempted),
          attempted_providers: Enum.reverse(result.attempted),
          attempts: length(result.attempted),
          geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          raw_response: first_result[:raw_response],
          collection_mode: true
        }

        response = %{
          latitude: lat,
          longitude: lng,
          city: first_result[:city],
          country: first_result[:country],
          geocoding_metadata: metadata,
          provider_ids: result.provider_ids
        }

        {:ok, response}

      nil ->
        # All providers failed
        Logger.error("❌ All #{length(result.attempted)} providers failed")

        metadata = %{
          attempted_providers: Enum.reverse(result.attempted),
          attempts: length(result.attempted),
          geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          all_failed: true
        }

        {:error, :all_failed, metadata}
    end
  end

  # Helper for try_all_providers - calls provider and updates accumulator
  defp call_provider_for_collection(address, provider_module, provider_name, acc) do
    case provider_module.geocode(address) do
      {:ok, %{latitude: lat, longitude: lng} = result} when is_float(lat) and is_float(lng) ->
        Logger.info("✅ #{provider_name} succeeded: #{lat}, #{lng}")

        # Extract provider_id from result
        provider_id = Map.get(result, :provider_id) || Map.get(result, :place_id)

        # Update accumulator
        acc
        |> Map.update!(:attempted, fn list -> [provider_name | list] end)
        |> Map.update!(:provider_ids, fn ids ->
          if provider_id, do: Map.put(ids, provider_name, provider_id), else: ids
        end)
        |> Map.update!(:first_success, fn
          nil -> {lat, lng, Map.put(result, :provider_name, provider_name)}
          # Keep first success
          existing -> existing
        end)
        |> Map.update!(:raw_responses, fn responses ->
          [%{provider: provider_name, response: Map.get(result, :raw_response)} | responses]
        end)

      {:error, reason} ->
        Logger.warning("⚠️ Provider #{provider_name} failed: #{inspect(reason)}")
        Map.update!(acc, :attempted, fn list -> [provider_name | list] end)

      other ->
        Logger.warning("⚠️ Provider #{provider_name} returned invalid format: #{inspect(other)}")
        Map.update!(acc, :attempted, fn list -> [provider_name | list] end)
    end
  end

  # Try providers recursively until one succeeds
  defp try_providers(_address, [], attempted) do
    # All providers failed
    Logger.error("❌ All #{length(attempted)} geocoding providers failed")

    metadata = %{
      attempted_providers: Enum.reverse(attempted),
      attempts: length(attempted),
      geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
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

        # Extract provider_id from result
        provider_id = Map.get(result, :provider_id) || Map.get(result, :place_id)

        # Build provider_ids map (only include if provider returned an ID)
        provider_ids =
          if provider_id do
            %{provider_name => provider_id}
          else
            %{}
          end

        metadata = %{
          provider: provider_name,
          attempted_providers: Enum.reverse([provider_name | attempted]),
          attempts: length(attempted) + 1,
          geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          raw_response: Map.get(result, :raw_response)
        }

        result
        |> Map.put(:geocoding_metadata, metadata)
        |> Map.put(:provider_ids, provider_ids)
        |> then(&{:ok, &1})

      {:error, reason} ->
        # Failed, try next provider
        Logger.warning("⚠️ Provider #{provider_name} failed: #{inspect(reason)}")
        try_providers(address, rest, [provider_name | attempted])

      other ->
        # Invalid response format
        Logger.warning("⚠️ Provider #{provider_name} returned invalid format: #{inspect(other)}")

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
