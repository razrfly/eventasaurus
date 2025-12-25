defmodule EventasaurusDiscovery.Sources.Inquizition.TransformerTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Inquizition.Transformer

  describe "transform_event/1" do
    test "transforms venue data with all required fields" do
      venue_data = %{
        venue_id: "97520779",
        name: "Andrea Ludgate Hill",
        address: "47 Ludgate Hill\nLondon\nEC4M 7JZ",
        latitude: 51.513898,
        longitude: -0.1026125,
        phone: "020 7236 1942",
        website: "https://andreabars.com/bookings/",
        email: "ludgatehill@andreabars.com",
        schedule_text: "Tuesdays, 6.30pm",
        day_filters: ["Tuesday"],
        timezone: "Europe/London",
        country: "GB"
      }

      event = Transformer.transform_event(venue_data)

      # Check required fields
      # External ID is venue-based only (NO date suffix) - one record per venue pattern
      # See docs/EXTERNAL_ID_CONVENTIONS.md - dates in recurring event IDs cause duplicates
      assert event.external_id == "inquizition_97520779"
      assert event.title == "Inquizition Trivia at Andrea Ludgate Hill"
      assert %DateTime{} = event.starts_at
      assert event.category == "trivia"

      # Check venue data
      assert event.venue_data.name == "Andrea Ludgate Hill"
      assert event.venue_data.address == "47 Ludgate Hill\nLondon\nEC4M 7JZ"
      assert event.venue_data.latitude == 51.513898
      assert event.venue_data.longitude == -0.1026125
      assert event.venue_data.phone == "020 7236 1942"
      assert event.venue_data.postcode == "EC4M 7JZ"
      assert event.venue_data.external_id == "inquizition_venue_97520779"

      # Check pricing
      assert event.is_ticketed == true
      assert event.is_free == false
      assert event.min_price == 2.50
      assert event.max_price == 2.50
      assert event.currency == "GBP"

      # Check recurrence rule
      assert is_map(event.recurrence_rule)
      assert event.recurrence_rule["frequency"] == "weekly"
      assert event.recurrence_rule["days_of_week"] == ["tuesday"]
      assert event.recurrence_rule["time"] == "18:30"
      assert event.recurrence_rule["timezone"] == "Europe/London"

      # Check metadata
      assert event.metadata.venue_id == "97520779"
      assert event.metadata.recurring == true
      assert event.metadata.frequency == "weekly"
      assert event.metadata.day_of_week == "tuesday"
      assert event.metadata.start_time == "18:30:00"
    end

    test "transforms venue with minimal data" do
      venue_data = %{
        venue_id: "123",
        name: "Test Venue",
        address: "Test Address\nLondon\nW1A 1AA",
        latitude: 51.5,
        longitude: -0.1,
        day_filters: ["Wednesday"],
        schedule_text: "Wednesdays, 7pm"
      }

      event = Transformer.transform_event(venue_data)

      # External ID is venue-based only (NO date suffix) - one record per venue pattern
      assert event.external_id == "inquizition_123"
      assert event.title == "Inquizition Trivia at Test Venue"
      assert event.venue_data.name == "Test Venue"
      assert event.min_price == 2.50
      assert event.currency == "GBP"
    end

    test "rejects venue when no day information available" do
      venue_data = %{
        venue_id: "123",
        name: "Test Venue",
        address: "Test Address",
        latitude: 51.5,
        longitude: -0.1,
        day_filters: [],
        schedule_text: nil
      }

      event = Transformer.transform_event(venue_data)

      assert event.external_id == "inquizition_123"

      # Should reject venue - no day information means no event
      assert event.recurrence_rule == nil
      assert event.starts_at == nil
    end

    test "extracts UK postcode from address" do
      venue_data = %{
        venue_id: "123",
        name: "Test Venue",
        address: "123 Test Street\nLondon\nEC4M 7JZ",
        latitude: 51.5,
        longitude: -0.1,
        day_filters: ["Monday"],
        schedule_text: "Mondays, 8pm"
      }

      event = Transformer.transform_event(venue_data)

      assert event.venue_data.postcode == "EC4M 7JZ"
    end

    test "sets country to United Kingdom" do
      venue_data = %{
        venue_id: "123",
        name: "Test Venue",
        address: "Test Address",
        latitude: 51.5,
        longitude: -0.1,
        day_filters: ["Thursday"],
        schedule_text: "Thursdays, 7:30pm"
      }

      event = Transformer.transform_event(venue_data)

      assert event.venue_data.country == "United Kingdom"
    end

    test "calculates ends_at as starts_at + 2 hours" do
      venue_data = %{
        venue_id: "123",
        name: "Test Venue",
        address: "Test Address",
        latitude: 51.5,
        longitude: -0.1,
        day_filters: ["Friday"],
        schedule_text: "Fridays, 8pm"
      }

      event = Transformer.transform_event(venue_data)

      assert %DateTime{} = event.starts_at
      assert %DateTime{} = event.ends_at

      # Check that ends_at is 2 hours after starts_at
      diff_seconds = DateTime.diff(event.ends_at, event.starts_at)
      # 2 hours = 7200 seconds
      assert diff_seconds == 7200
    end

    test "includes no image_url (not available from source)" do
      venue_data = %{
        venue_id: "123",
        name: "Test Venue",
        address: "Test Address",
        latitude: 51.5,
        longitude: -0.1,
        day_filters: ["Saturday"],
        schedule_text: "Saturdays, 6pm"
      }

      event = Transformer.transform_event(venue_data)

      assert event.image_url == nil
    end
  end

  describe "parse_schedule/2" do
    test "parses Tuesday 6.30pm from filters and schedule text" do
      {day, time, starts_at, recurrence_rule} =
        Transformer.parse_schedule(["Tuesday"], "Tuesdays, 6.30pm")

      assert day == :tuesday
      assert time == ~T[18:30:00]
      assert %DateTime{} = starts_at
      assert recurrence_rule["frequency"] == "weekly"
      assert recurrence_rule["days_of_week"] == ["tuesday"]
      assert recurrence_rule["time"] == "18:30"
      assert recurrence_rule["timezone"] == "Europe/London"
    end

    test "parses Wednesday 7pm" do
      {day, time, _starts_at, _recurrence_rule} =
        Transformer.parse_schedule(["Wednesday"], "Wednesdays, 7pm")

      assert day == :wednesday
      assert time == ~T[19:00:00]
    end

    test "returns nil when no day information available" do
      {day, time, starts_at, recurrence_rule} =
        Transformer.parse_schedule([], nil)

      # Should reject - no day information
      assert day == nil
      assert time == nil
      assert starts_at == nil
      assert recurrence_rule == nil
    end

    test "uses time fallback when day present but time missing" do
      {day, time, starts_at, recurrence_rule} =
        Transformer.parse_schedule(["Wednesday"], "Wednesdays")

      # Should parse day and use 8:00 PM fallback for time
      assert day == :wednesday
      assert time == ~T[20:00:00]
      assert %DateTime{} = starts_at

      assert is_map(recurrence_rule)
      assert recurrence_rule["frequency"] == "weekly"
      assert recurrence_rule["days_of_week"] == ["wednesday"]
      assert recurrence_rule["time"] == "20:00"
      assert recurrence_rule["schedule_inferred"] == true
    end

    test "prioritizes day from filters over schedule text" do
      {day, _time, _starts_at, _recurrence_rule} =
        Transformer.parse_schedule(["Thursday"], "Wednesdays, 7pm")

      # Should use Thursday from filters, not Wednesday from text
      assert day == :thursday
    end
  end

  describe "resolve_location/3" do
    test "returns United Kingdom as country" do
      {_city, country} = Transformer.resolve_location(51.5, -0.1, "Test Address")

      assert country == "United Kingdom"
    end

    test "handles nil coordinates gracefully" do
      {_city, country} = Transformer.resolve_location(nil, nil, "London\nUK")

      assert country == "United Kingdom"
    end
  end
end
