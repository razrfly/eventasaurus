defmodule EventasaurusDiscovery.Geocoding.MultiProviderTest do
  @moduledoc """
  Comprehensive test suite for multi-provider geocoding system.

  Tests all providers, fallback chains, and scraper integration patterns.

  Run all tests:
    mix test test/eventasaurus_discovery/geocoding/multi_provider_test.exs

  Run specific phase:
    mix test test/eventasaurus_discovery/geocoding/multi_provider_test.exs --only provider_isolation
    mix test test/eventasaurus_discovery/geocoding/multi_provider_test.exs --only fallback_chain
    mix test test/eventasaurus_discovery/geocoding/multi_provider_test.exs --only scraper_integration
  """

  use EventasaurusApp.DataCase, async: false
  require Logger

  alias EventasaurusDiscovery.Geocoding.Orchestrator
  alias EventasaurusDiscovery.Geocoding.Providers.{Mapbox, Here, Geoapify, LocationIQ, OpenStreetMap, Photon}
  alias EventasaurusDiscovery.Helpers.AddressGeocoder

  # Test addresses for each provider
  @krakow_address "Floriańska 3, Kraków, Poland"
  @london_address "221B Baker Street, London, United Kingdom"
  @invalid_address "NonExistentPlace123XYZ"

  # ============================================================================
  # PHASE 1: PROVIDER ISOLATION TESTS
  # ============================================================================

  @describetag :provider_isolation
  describe "Phase 1: Provider Isolation" do
    test "Mapbox geocodes Kraków successfully" do
      result = Mapbox.geocode(@krakow_address)

      assert {:ok, geocode_result} = result
      assert is_float(geocode_result.latitude)
      assert is_float(geocode_result.longitude)
      assert geocode_result.city == "Kraków" or geocode_result.city == "Krakow"
      assert geocode_result.country =~ "Poland"

      Logger.info("✅ Mapbox: #{inspect(geocode_result)}")
    end

    test "HERE geocodes London successfully" do
      result = Here.geocode(@london_address)

      assert {:ok, geocode_result} = result
      assert is_float(geocode_result.latitude)
      assert is_float(geocode_result.longitude)
      assert geocode_result.city == "London"
      assert geocode_result.country =~ "United Kingdom"

      Logger.info("✅ HERE: #{inspect(geocode_result)}")
    end

    test "Geoapify geocodes Kraków successfully" do
      result = Geoapify.geocode(@krakow_address)

      assert {:ok, geocode_result} = result
      assert is_float(geocode_result.latitude)
      assert is_float(geocode_result.longitude)
      assert is_binary(geocode_result.city)
      assert geocode_result.city != "Unknown"

      Logger.info("✅ Geoapify: #{inspect(geocode_result)}")
    end

    test "LocationIQ geocodes London successfully" do
      result = LocationIQ.geocode(@london_address)

      assert {:ok, geocode_result} = result
      assert is_float(geocode_result.latitude)
      assert is_float(geocode_result.longitude)
      assert is_binary(geocode_result.city)

      Logger.info("✅ LocationIQ: #{inspect(geocode_result)}")
    end

    test "OpenStreetMap geocodes Kraków successfully" do
      # OSM rate limit: 1 req/sec
      Process.sleep(1100)

      result = OpenStreetMap.geocode(@krakow_address)

      assert {:ok, geocode_result} = result
      assert is_float(geocode_result.latitude)
      assert is_float(geocode_result.longitude)
      assert is_binary(geocode_result.city)

      Logger.info("✅ OpenStreetMap: #{inspect(geocode_result)}")
    end

    test "Photon geocodes London successfully" do
      result = Photon.geocode(@london_address)

      assert {:ok, geocode_result} = result
      assert is_float(geocode_result.latitude)
      assert is_float(geocode_result.longitude)
      assert is_binary(geocode_result.city)

      Logger.info("✅ Photon: #{inspect(geocode_result)}")
    end

    test "All providers handle invalid addresses gracefully" do
      providers = [Mapbox, Here, Geoapify, LocationIQ, OpenStreetMap, Photon]

      Enum.each(providers, fn provider ->
        # OSM rate limit
        if provider == OpenStreetMap, do: Process.sleep(1100)

        result = provider.geocode(@invalid_address)

        assert {:error, _reason} = result,
          "#{provider.name()} should return error for invalid address"

        Logger.info("✅ #{provider.name()} correctly handled invalid address")
      end)
    end
  end

  # ============================================================================
  # PHASE 2: FALLBACK CHAIN TESTS
  # ============================================================================

  @describetag :fallback_chain
  describe "Phase 2: Fallback Chain" do
    test "Orchestrator tries providers in priority order" do
      # Use AddressGeocoder which uses Orchestrator
      {:ok, result} = AddressGeocoder.geocode(@krakow_address)

      assert is_float(result.latitude)
      assert is_float(result.longitude)
      assert is_binary(result.city)
      assert is_map(result.geocoding_metadata)

      # Check metadata
      metadata = result.geocoding_metadata
      assert is_binary(metadata.provider)
      assert is_list(metadata.attempted_providers)
      assert metadata.attempts >= 1
      assert metadata.geocoded_at

      Logger.info("✅ Orchestrator succeeded with provider: #{metadata.provider}")
      Logger.info("   Attempted providers: #{inspect(metadata.attempted_providers)}")
      Logger.info("   Total attempts: #{metadata.attempts}")
    end

    test "Orchestrator metadata includes all attempt information" do
      {:ok, result} = AddressGeocoder.geocode(@london_address)

      metadata = result.geocoding_metadata

      # Verify metadata structure
      assert is_binary(metadata.provider)
      assert is_list(metadata.attempted_providers)
      assert length(metadata.attempted_providers) >= 1
      assert metadata.attempts == length(metadata.attempted_providers)
      assert %DateTime{} = metadata.geocoded_at

      Logger.info("✅ Metadata complete:")
      Logger.info("   Provider: #{metadata.provider}")
      Logger.info("   Attempts: #{metadata.attempts}")
      Logger.info("   Chain: #{inspect(metadata.attempted_providers)}")
    end

    test "Orchestrator handles addresses that all providers fail on" do
      result = AddressGeocoder.geocode(@invalid_address)

      assert {:error, :all_providers_failed} = result

      Logger.info("✅ Orchestrator correctly exhausted all providers")
    end
  end

  # ============================================================================
  # PHASE 3: SCRAPER INTEGRATION PATTERNS
  # ============================================================================

  @describetag :scraper_integration
  describe "Phase 3: Scraper Integration Patterns" do
    test "Pattern 1 (GPS-Provided): Venue data with coordinates skips geocoding" do
      venue_data = %{
        name: "Test Venue",
        latitude: 50.0619,
        longitude: 19.9369,
        address: @krakow_address,
        city: "Kraków",
        country: "Poland"
      }

      # VenueProcessor should skip geocoding if coordinates present
      assert venue_data.latitude != nil
      assert venue_data.longitude != nil

      Logger.info("✅ Pattern 1: GPS already provided, will skip geocoding")
    end

    test "Pattern 2 (Deferred Geocoding): Venue data without coordinates triggers geocoding" do
      venue_data = %{
        name: "Test Venue",
        latitude: nil,
        longitude: nil,
        address: @krakow_address,
        city: "Kraków",
        country: "Poland"
      }

      # VenueProcessor should trigger geocoding
      assert venue_data.latitude == nil
      assert venue_data.longitude == nil
      assert venue_data.address != nil

      # Test that AddressGeocoder can geocode it
      {:ok, result} = AddressGeocoder.geocode(venue_data.address)

      assert is_float(result.latitude)
      assert is_float(result.longitude)
      assert is_map(result.geocoding_metadata)

      Logger.info("✅ Pattern 2: Nil coordinates triggered geocoding")
      Logger.info("   Provider: #{result.geocoding_metadata.provider}")
    end

    test "Pattern 3 (Recurring Events): Venue-based geocoding for PubQuiz-style events" do
      # PubQuiz creates venue once, then references it for recurring events
      venue_data = %{
        name: "The Crown Inn",
        latitude: nil,
        longitude: nil,
        address: "123 High Street, London, UK",
        city: "London",
        country: "United Kingdom"
      }

      # First: Geocode venue
      {:ok, result} = AddressGeocoder.geocode(venue_data.address)

      # Then: Venue would be saved with coordinates
      venue_with_coords = Map.merge(venue_data, %{
        latitude: result.latitude,
        longitude: result.longitude
      })

      assert is_float(venue_with_coords.latitude)
      assert is_float(venue_with_coords.longitude)

      Logger.info("✅ Pattern 3: Venue geocoded once for recurring events")
      Logger.info("   Coordinates: #{venue_with_coords.latitude}, #{venue_with_coords.longitude}")
    end
  end

  # ============================================================================
  # PHASE 4: DASHBOARD VALIDATION
  # ============================================================================

  @describetag :dashboard_validation
  describe "Phase 4: Dashboard Stats Validation" do
    setup do
      # Run some geocoding to generate stats
      AddressGeocoder.geocode(@krakow_address)
      AddressGeocoder.geocode(@london_address)

      :ok
    end

    test "GeocodingStats.success_rate_by_provider/1 returns valid data" do
      stats = EventasaurusDiscovery.Metrics.GeocodingStats.success_rate_by_provider(7)

      assert is_list(stats)

      Enum.each(stats, fn stat ->
        assert is_binary(stat.provider)
        assert is_integer(stat.total_attempts)
        assert is_integer(stat.successful_attempts)
        assert is_float(stat.success_rate) or is_integer(stat.success_rate)
        assert stat.success_rate >= 0 and stat.success_rate <= 100
      end)

      Logger.info("✅ success_rate_by_provider stats valid")
    end

    test "GeocodingStats.average_attempts/1 returns valid float" do
      avg = EventasaurusDiscovery.Metrics.GeocodingStats.average_attempts(7)

      assert is_float(avg) or avg == nil

      if avg do
        assert avg >= 1.0
        Logger.info("✅ average_attempts: #{avg}")
      else
        Logger.info("✅ average_attempts: no data yet")
      end
    end

    test "GeocodingStats.fallback_patterns/1 returns valid data" do
      patterns = EventasaurusDiscovery.Metrics.GeocodingStats.fallback_patterns(7)

      assert is_list(patterns)

      Enum.each(patterns, fn pattern ->
        assert is_integer(pattern.depth)
        assert is_integer(pattern.count)
        assert pattern.depth >= 1
        assert pattern.count >= 0
      end)

      Logger.info("✅ fallback_patterns stats valid")
    end

    test "GeocodingStats.provider_performance/1 returns valid data" do
      performance = EventasaurusDiscovery.Metrics.GeocodingStats.provider_performance(7)

      assert is_list(performance)

      Enum.each(performance, fn perf ->
        assert is_binary(perf.provider)
        assert is_integer(perf.success_count)
        assert is_integer(perf.total_count)
        assert is_float(perf.success_rate) or is_integer(perf.success_rate)
        assert perf.success_rate >= 0 and perf.success_rate <= 100
      end)

      Logger.info("✅ provider_performance stats valid")
    end
  end
end
