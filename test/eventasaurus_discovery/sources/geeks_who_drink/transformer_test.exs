defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.TransformerTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Transformer

  describe "resolve_location/3" do
    test "resolves city from valid GPS coordinates" do
      # New York coordinates
      {city, country} =
        Transformer.resolve_location(40.7128, -74.0060, "123 Main St, New York, NY 10001")

      assert is_binary(city)
      assert city != nil
      assert country == "United States"
      # Should be a valid city name, not garbage
      refute city =~ ~r/^\d+$/
      refute city =~ ~r/street|road|avenue/i
    end

    test "resolves city from coordinates with garbage address" do
      # Chicago coordinates with intentionally bad address
      {city, country} =
        Transformer.resolve_location(
          41.8781,
          -87.6298,
          "SW18 2SS, 123 Street Name, England"
        )

      # Should use coordinates, ignore garbage address
      assert is_binary(city)
      assert city != nil
      assert country == "United States"
      # Should be Chicago or nearby city
      assert city != "SW18 2SS"
      assert city != "123 Street Name"
    end

    test "handles missing coordinates with valid address" do
      # No coordinates - should parse address conservatively
      {city, country} =
        Transformer.resolve_location(
          nil,
          nil,
          "123 Main Street, Chicago, IL 60601"
        )

      # Conservative parser requires 3+ parts and validation
      assert city == "Chicago"
      assert country == "United States"
    end

    test "handles missing coordinates with invalid address" do
      # No coordinates, garbage address - should return nil
      {city, country} =
        Transformer.resolve_location(nil, nil, "SW18 2SS, England")

      assert city == nil
      assert country == "United States"
    end

    test "validates address parsing candidates" do
      # Address with postcode instead of city
      {city, country} =
        Transformer.resolve_location(nil, nil, "13 Bollo Lane, 90210, CA")

      # Should reject "90210" as invalid city
      assert city == nil
      assert country == "United States"
    end

    test "handles malformed addresses gracefully" do
      {city, country} = Transformer.resolve_location(nil, nil, "Just a random string")

      assert city == nil
      assert country == "United States"
    end
  end

  describe "transform_event/2" do
    test "uses geocoding for city resolution" do
      venue_data = %{
        venue_id: "12345",
        title: "The Trivia Bar",
        address: "123 Main St, New York, NY 10001",
        latitude: 40.7128,
        longitude: -74.0060,
        starts_at: ~U[2025-10-15 19:00:00Z],
        source_url: "https://example.com/venue/12345",
        time_text: "Tuesdays at 7:00 pm",
        fee_text: "$5 per person"
      }

      result = Transformer.transform_event(venue_data)

      # Should have resolved city from coordinates
      assert result.venue_data.city != nil
      assert is_binary(result.venue_data.city)
      # Should not be garbage data
      refute result.venue_data.city =~ ~r/^\d+$/
      refute result.venue_data.city =~ ~r/street|road|avenue/i
      # Should be a real city name
      assert String.length(result.venue_data.city) > 1
    end

    test "handles venues with missing coordinates gracefully" do
      venue_data = %{
        venue_id: "12345",
        title: "The Trivia Bar",
        address: "123 Main St, Chicago, IL 60601",
        latitude: nil,
        longitude: nil,
        starts_at: ~U[2025-10-15 19:00:00Z],
        source_url: "https://example.com/venue/12345",
        time_text: "Tuesdays at 7:00 pm"
      }

      result = Transformer.transform_event(venue_data)

      # Should fall back to conservative address parsing
      assert result.venue_data.city == "Chicago"
      assert result.venue_data.country == "United States"
    end

    test "prefers nil over garbage city data" do
      venue_data = %{
        venue_id: "12345",
        title: "The Trivia Bar",
        address: "13 Bollo Lane, SW18 2SS, England",
        latitude: nil,
        longitude: nil,
        starts_at: ~U[2025-10-15 19:00:00Z],
        source_url: "https://example.com/venue/12345",
        time_text: "Tuesdays at 7:00 pm"
      }

      result = Transformer.transform_event(venue_data)

      # Should return nil rather than garbage
      assert result.venue_data.city == nil
      assert result.venue_data.country == "United States"
    end

    test "complete transformation with valid data" do
      venue_data = %{
        venue_id: "12345",
        title: "The Trivia Bar",
        address: "123 Main St, New York, NY 10001",
        latitude: 40.7128,
        longitude: -74.0060,
        starts_at: ~U[2025-10-15 19:00:00Z],
        source_url: "https://example.com/venue/12345",
        time_text: "Tuesdays at 7:00 pm",
        fee_text: "$5 per person",
        phone: "555-1234",
        website: "https://example.com"
      }

      result = Transformer.transform_event(venue_data)

      # Verify all required fields
      assert result.external_id == "geeks_who_drink_12345"
      assert result.title == "Geeks Who Drink Trivia at The Trivia Bar"
      assert result.starts_at == ~U[2025-10-15 19:00:00Z]
      assert result.category == "trivia"

      # Verify venue data
      assert result.venue_data.name == "The Trivia Bar"
      assert result.venue_data.address == "123 Main St, New York, NY 10001"
      assert result.venue_data.city != nil
      assert result.venue_data.country == "United States"
      assert result.venue_data.latitude == 40.7128
      assert result.venue_data.longitude == -74.0060
      assert result.venue_data.phone == "555-1234"
      assert result.venue_data.website == "https://example.com"

      # Verify pricing
      assert result.is_free == false
      assert result.is_ticketed == true
      assert result.min_price == Decimal.new("5")

      # Verify recurrence
      assert result.recurrence_rule != nil
      assert result.recurrence_rule["frequency"] == "weekly"
      assert result.recurrence_rule["days_of_week"] == ["tuesday"]
      assert result.recurrence_rule["time"] == "19:00"
    end
  end
end
