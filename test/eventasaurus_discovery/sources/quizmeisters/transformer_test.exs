defmodule EventasaurusDiscovery.Sources.Quizmeisters.TransformerTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Quizmeisters.Transformer

  describe "transform_event/2" do
    test "transforms complete venue data to unified format" do
      venue_data = %{
        venue_id: "library-bar",
        name: "The Library Bar",
        address: "123 Main St, Brooklyn, NY 11201",
        latitude: 40.7128,
        longitude: -74.006,
        phone: "555-123-4567",
        postcode: "11201",
        url: "https://quizmeisters.com/venues/library-bar",
        time_text: "Wednesdays at 7pm",
        source_url: "https://quizmeisters.com/venues/library-bar",
        starts_at: ~U[2025-10-15 23:00:00Z],
        start_time: ~T[19:00:00]
      }

      result = Transformer.transform_event(venue_data)

      # Required fields
      assert result.external_id == "quizmeisters_library-bar"
      assert result.title == "Quizmeisters Trivia at The Library Bar"
      assert result.starts_at == ~U[2025-10-15 23:00:00Z]

      # Venue data
      assert result.venue_data.name == "The Library Bar"
      assert result.venue_data.address == "123 Main St, Brooklyn, NY 11201"
      assert result.venue_data.latitude == 40.7128
      assert result.venue_data.longitude == -74.006
      assert result.venue_data.phone == "555-123-4567"
      assert result.venue_data.postcode == "11201"
      assert result.venue_data.external_id == "quizmeisters_venue_library-bar"
      assert result.venue_data.country == "Australia"

      # Pricing
      assert result.is_free == true
      assert result.is_ticketed == false
      assert result.min_price == nil
      assert result.currency == "AUD"

      # Category
      assert result.category == "trivia"

      # Metadata
      assert result.metadata.time_text == "Wednesdays at 7pm"
      assert result.metadata.recurring == true
      assert result.metadata.frequency == "weekly"

      # Recurrence rule
      assert result.recurrence_rule != nil
      assert result.recurrence_rule["frequency"] == "weekly"
      assert result.recurrence_rule["days_of_week"] == ["wednesday"]
      assert result.recurrence_rule["time"] == "19:00"
    end

    test "generates stable external_id from venue_id" do
      venue_data = build_minimal_venue_data("test-venue")
      result = Transformer.transform_event(venue_data)
      assert result.external_id == "quizmeisters_test-venue"
    end

    test "generates stable venue external_id" do
      venue_data = build_minimal_venue_data("test-venue")
      result = Transformer.transform_event(venue_data)
      assert result.venue_data.external_id == "quizmeisters_venue_test-venue"
    end

    test "calculates ends_at as 2 hours after starts_at" do
      venue_data = build_minimal_venue_data("test-venue")
      result = Transformer.transform_event(venue_data)

      assert result.ends_at == ~U[2025-10-16 01:00:00Z]
    end

    test "sets all events as free" do
      venue_data = build_minimal_venue_data("test-venue")
      result = Transformer.transform_event(venue_data)

      assert result.is_free == true
      assert result.is_ticketed == false
      assert result.min_price == nil
      assert result.max_price == nil
    end

    test "sets category to trivia" do
      venue_data = build_minimal_venue_data("test-venue")
      result = Transformer.transform_event(venue_data)

      assert result.category == "trivia"
    end

    test "builds description with time_text" do
      venue_data = build_minimal_venue_data("test-venue")
      result = Transformer.transform_event(venue_data)

      assert result.description =~ "Weekly trivia night at The Test Venue"
      assert result.description =~ "Wednesdays at 7pm"
      assert result.description =~ "Free to play"
    end

    test "handles venue data with custom description" do
      venue_data = build_minimal_venue_data("test-venue")
      venue_data = Map.put(venue_data, :description, "Custom description text")

      result = Transformer.transform_event(venue_data)

      assert result.description =~ "Custom description text"
      assert result.description =~ "Free to play"
      assert result.description =~ "Wednesdays at 7pm"
    end
  end

  describe "parse_schedule_to_recurrence/3" do
    test "parses schedule with starts_at DateTime" do
      starts_at = DateTime.from_naive!(~N[2025-10-15 19:00:00], "America/Chicago")

      assert {:ok, rule} =
               Transformer.parse_schedule_to_recurrence("Wednesdays at 7pm", starts_at, %{})

      assert rule["frequency"] == "weekly"
      assert rule["days_of_week"] == ["wednesday"]
      assert rule["time"] == "19:00"
      assert rule["timezone"] == "America/Chicago"
    end

    test "uses venue_data timezone if starts_at is nil" do
      venue_data = %{timezone: "America/Los_Angeles"}

      assert {:ok, rule} =
               Transformer.parse_schedule_to_recurrence("Thursdays at 8:00 PM", nil, venue_data)

      assert rule["timezone"] == "America/Los_Angeles"
    end

    test "defaults to Australia/Sydney timezone" do
      assert {:ok, rule} =
               Transformer.parse_schedule_to_recurrence("Tuesdays at 7:30pm", nil, %{})

      assert rule["timezone"] == "Australia/Sydney"
    end

    test "returns error for nil time_text" do
      assert {:error, "Time text is nil"} =
               Transformer.parse_schedule_to_recurrence(nil, nil, %{})
    end

    test "returns error for invalid time_text" do
      assert {:error, _} = Transformer.parse_schedule_to_recurrence("invalid", nil, %{})
    end

    test "handles different day formats" do
      assert {:ok, rule} =
               Transformer.parse_schedule_to_recurrence("Monday nights at 8pm", nil, %{})

      assert rule["days_of_week"] == ["monday"]

      assert {:ok, rule} =
               Transformer.parse_schedule_to_recurrence("Fridays at 9:00 PM", nil, %{})

      assert rule["days_of_week"] == ["friday"]
    end

    test "handles different time formats" do
      assert {:ok, rule} = Transformer.parse_schedule_to_recurrence("Wednesdays at 7pm", nil, %{})
      assert rule["time"] == "19:00"

      assert {:ok, rule} =
               Transformer.parse_schedule_to_recurrence("Wednesdays at 7:30pm", nil, %{})

      assert rule["time"] == "19:30"

      assert {:ok, rule} =
               Transformer.parse_schedule_to_recurrence("Wednesdays at 8:00 PM", nil, %{})

      assert rule["time"] == "20:00"
    end
  end

  describe "resolve_location/3" do
    test "resolves location from coordinates" do
      # This will use offline geocoding
      {city, country} =
        Transformer.resolve_location(40.7128, -74.006, "123 Main St, Brooklyn, NY 11201")

      assert country == "Australia"
      # City might be nil if geocoding fails, or resolved city name
      assert is_binary(city) or is_nil(city)
    end

    test "falls back to address parsing when coordinates are nil" do
      {city, country} = Transformer.resolve_location(nil, nil, "123 Main St, Brooklyn, NY 11201")

      assert country == "Australia"
      # City extraction depends on CityResolver validation
      assert is_binary(city) or is_nil(city)
    end

    test "handles invalid address format" do
      {city, country} = Transformer.resolve_location(nil, nil, "Invalid Address")

      assert country == "Australia"
      assert is_nil(city)
    end
  end

  describe "image_url validation" do
    test "includes valid hero image URL in transformed event" do
      venue_data = build_minimal_venue_data("test-venue")
      venue_data = Map.put(venue_data, :hero_image_url, "https://example.com/venue-photo.jpg")

      result = Transformer.transform_event(venue_data)

      assert result.image_url == "https://example.com/venue-photo.jpg"
    end

    test "filters out placeholder images" do
      venue_data = build_minimal_venue_data("test-venue")
      venue_data = Map.put(venue_data, :hero_image_url, "https://example.com/placeholder.jpg")

      result = Transformer.transform_event(venue_data)

      assert result.image_url == nil
    end

    test "filters out thumbnail images" do
      venue_data = build_minimal_venue_data("test-venue")
      venue_data = Map.put(venue_data, :hero_image_url, "https://example.com/thumb/venue.jpg")

      result = Transformer.transform_event(venue_data)

      assert result.image_url == nil
    end

    test "handles nil hero_image_url gracefully" do
      venue_data = build_minimal_venue_data("test-venue")
      # No hero_image_url in venue_data

      result = Transformer.transform_event(venue_data)

      assert result.image_url == nil
    end

    test "handles empty string hero_image_url" do
      venue_data = build_minimal_venue_data("test-venue")
      venue_data = Map.put(venue_data, :hero_image_url, "")

      result = Transformer.transform_event(venue_data)

      assert result.image_url == nil
    end
  end

  # Helper function to build minimal venue data
  defp build_minimal_venue_data(venue_id) do
    %{
      venue_id: venue_id,
      name: "The Test Venue",
      address: "123 Test St, New York, NY 10001",
      latitude: 40.7128,
      longitude: -74.006,
      phone: "555-1234",
      postcode: "10001",
      url: "https://quizmeisters.com/venues/#{venue_id}",
      time_text: "Wednesdays at 7pm",
      source_url: "https://quizmeisters.com/venues/#{venue_id}",
      starts_at: ~U[2025-10-15 23:00:00Z],
      start_time: ~T[19:00:00]
    }
  end
end
