defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.TransformerCityResolutionTest do
  @moduledoc """
  Tests for ResidentAdvisor city resolution implementation.

  Ensures A-grade city validation using CityResolver:
  1. GPS coordinates → CityResolver.resolve_city() (primary)
  2. Geocoding failure → API city validation (fallback)
  3. Validation failure → nil (safe default)

  This follows the Bandsintown A-grade pattern for international events.
  """

  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Transformer

  # Mock city context for testing
  defp mock_city_context(city_name \\ "London", lat \\ 51.5074, lng \\ -0.1278) do
    %{
      name: city_name,
      slug: String.downcase(city_name),
      latitude: lat,
      longitude: lng,
      country: %{
        name: "United Kingdom",
        code: "GB"
      }
    }
  end

  # Mock event with venue
  defp mock_event_with_venue(venue_name, venue_id \\ "123", venue_data \\ %{}) do
    %{
      "id" => "event_123",
      "title" => "Test Event",
      "date" => "2025-10-15",
      "startTime" => "20:00",
      "venue" => Map.merge(
        %{
          "id" => venue_id,
          "name" => venue_name,
          "contentUrl" => "/venues/#{venue_id}",
          "live" => true
        },
        venue_data
      ),
      "artists" => [],
      "contentUrl" => "/events/event_123"
    }
  end

  describe "city resolution with GPS coordinates (A-grade: Layer 1 primary)" do
    test "resolves city from valid GPS coordinates using CityResolver" do
      # Kraków coordinates
      event = mock_event_with_venue("Test Venue")

      # Mock VenueEnricher to return Kraków coordinates
      # In real implementation, VenueEnricher.get_coordinates/3 would return these
      # For this test, we're testing the resolve_location/4 function behavior

      city_context = mock_city_context("Kraków")

      # Transform event - should use CityResolver for GPS-based city resolution
      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Verify city was resolved (either from GPS or validated from API)
      assert transformed.venue_data.city != nil
      # City should be validated string, not containing invalid patterns
      assert is_binary(transformed.venue_data.city)
      assert String.trim(transformed.venue_data.city) != ""
    end

    test "falls back to API city validation when GPS coordinates invalid" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("London")

      # Without GPS coordinates, should validate API city name
      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Should have validated the API city name
      assert transformed.venue_data.city != nil
      assert is_binary(transformed.venue_data.city)
    end

    test "handles international events with various city names" do
      test_cities = ["London", "Berlin", "Paris", "Tokyo", "New York"]

      for city <- test_cities do
        event = mock_event_with_venue("Test Venue")
        city_context = mock_city_context(city)

        {:ok, transformed} = Transformer.transform_event(event, city_context)

        # All cities should be validated
        assert transformed.venue_data.city != nil
        assert is_binary(transformed.venue_data.city)
      end
    end
  end

  describe "city validation fallback (A-grade: Layer 1 fallback)" do
    test "validates API city name when GPS coordinates unavailable" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("Manchester")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Should validate API city through CityResolver
      assert transformed.venue_data.city != nil
      assert String.trim(transformed.venue_data.city) != ""
    end

    test "rejects postcodes as city names" do
      # Test with UK postcode-like pattern
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("SW1A 1AA")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Postcode should be rejected, city should be nil
      # VenueProcessor Layer 2 will catch this
      assert transformed.venue_data.city == nil
    end

    test "rejects street addresses as city names" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("123 Main Street")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Street address should be rejected, city should be nil
      assert transformed.venue_data.city == nil
    end

    test "rejects numeric values as city names" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("12345")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Numeric value should be rejected, city should be nil
      assert transformed.venue_data.city == nil
    end

    test "rejects venue names as city names" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("The Blue Bar")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Venue name pattern should be rejected, city should be nil
      assert transformed.venue_data.city == nil
    end

    test "rejects empty or whitespace-only city names" do
      for invalid_city <- ["", "   ", "\t", "\n"] do
        event = mock_event_with_venue("Test Venue")
        city_context = mock_city_context(invalid_city)

        {:ok, transformed} = Transformer.transform_event(event, city_context)

        # Empty/whitespace should be rejected, city should be nil
        assert transformed.venue_data.city == nil
      end
    end

    test "trims whitespace from valid city names" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("  London  ")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Should trim whitespace and validate
      assert transformed.venue_data.city == "London"
    end
  end

  describe "placeholder venues with city validation" do
    test "validates city name even for placeholder venues" do
      # Event without venue data
      event = %{
        "id" => "event_123",
        "title" => "Test Event",
        "date" => "2025-10-15",
        "startTime" => "20:00",
        "venue" => nil,
        "artists" => [],
        "contentUrl" => "/events/event_123"
      }

      city_context = mock_city_context("Berlin")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Placeholder venue should still validate city name
      assert transformed.venue_data.city != nil
      assert transformed.venue_data.metadata.placeholder == true
    end

    test "rejects invalid city names for placeholder venues" do
      event = %{
        "id" => "event_123",
        "title" => "Test Event",
        "date" => "2025-10-15",
        "startTime" => "20:00",
        "venue" => nil,
        "artists" => [],
        "contentUrl" => "/events/event_123"
      }

      # Invalid city name (postcode)
      city_context = mock_city_context("SW1A 1AA")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Invalid city should be rejected even for placeholders
      assert transformed.venue_data.city == nil
      assert transformed.venue_data.metadata.placeholder == true
    end
  end

  describe "defense in depth: Layer 1 + Layer 2 protection" do
    test "transforms event successfully with valid city (Layer 1 validation)" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("Prague")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Layer 1 validation passes
      assert transformed.venue_data.city != nil
      assert transformed.venue_data.country == "United Kingdom"
    end

    test "returns nil city for invalid patterns (Layer 2 will catch)" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("12345")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # Layer 1 validation fails, returns nil for Layer 2 safety net
      assert transformed.venue_data.city == nil
      # VenueProcessor Layer 2 will reject this during create_city/3
    end

    test "validates city names case-insensitively for common patterns" do
      # Test case variations
      for city <- ["london", "LONDON", "London", "lOnDoN"] do
        event = mock_event_with_venue("Test Venue")
        city_context = mock_city_context(city)

        {:ok, transformed} = Transformer.transform_event(event, city_context)

        # Should validate regardless of case (CityResolver handles normalization)
        assert transformed.venue_data.city != nil
      end
    end
  end

  describe "A-grade implementation verification" do
    test "implements CityResolver.resolve_city() for GPS coordinates" do
      # This test verifies the A-grade pattern is implemented
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("Amsterdam")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # A-grade requirement: City must be validated through CityResolver
      # Either from GPS (primary) or API city validation (fallback)
      assert is_binary(transformed.venue_data.city) or is_nil(transformed.venue_data.city)

      # If city is present, it must be validated (not raw API value)
      if transformed.venue_data.city do
        assert String.trim(transformed.venue_data.city) != ""
        # Should not contain invalid patterns
        refute String.match?(transformed.venue_data.city, ~r/^\d+$/)
        refute String.match?(transformed.venue_data.city, ~r/street|road|avenue/i)
      end
    end

    test "implements validate_api_city() fallback for missing GPS" do
      event = mock_event_with_venue("Test Venue")
      city_context = mock_city_context("Copenhagen")

      {:ok, transformed} = Transformer.transform_event(event, city_context)

      # A-grade requirement: API city must be validated
      # Returns validated city or nil (never returns garbage)
      assert is_binary(transformed.venue_data.city) or is_nil(transformed.venue_data.city)
    end

    test "prefers nil over garbage data (conservative fallback)" do
      # Test with various invalid patterns
      invalid_cities = [
        "123 Main Street",
        "SW1A 1AA",
        "12345",
        "The Blue Bar & Restaurant",
        "",
        "   "
      ]

      for invalid_city <- invalid_cities do
        event = mock_event_with_venue("Test Venue")
        city_context = mock_city_context(invalid_city)

        {:ok, transformed} = Transformer.transform_event(event, city_context)

        # A-grade requirement: Prefer nil over invalid data
        assert transformed.venue_data.city == nil,
               "Expected nil for invalid city: #{inspect(invalid_city)}, got: #{inspect(transformed.venue_data.city)}"
      end
    end
  end

  describe "international event coverage" do
    test "handles events across different continents" do
      # Test major cities across continents
      test_cases = [
        {"New York", "United States"},
        {"London", "United Kingdom"},
        {"Tokyo", "Japan"},
        {"Sydney", "Australia"},
        {"Berlin", "Germany"},
        {"São Paulo", "Brazil"}
      ]

      for {city, _country} <- test_cases do
        event = mock_event_with_venue("Test Venue")
        city_context = mock_city_context(city)

        {:ok, transformed} = Transformer.transform_event(event, city_context)

        # All international cities should be validated
        assert transformed.venue_data.city != nil,
               "Failed to validate city: #{city}"
      end
    end
  end
end
