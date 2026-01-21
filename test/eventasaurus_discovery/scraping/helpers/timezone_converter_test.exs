defmodule EventasaurusDiscovery.Scraping.Helpers.TimezoneConverterTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Scraping.Helpers.TimezoneConverter

  describe "convert_local_to_utc/2" do
    test "converts New York time to UTC (EST/UTC-5)" do
      # 8:00 PM EST (winter) should become 1:00 AM UTC next day
      naive_dt = ~N[2025-01-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "America/New_York")

      assert utc_dt.day == 17
      assert utc_dt.hour == 1
      assert utc_dt.minute == 0
      assert utc_dt.time_zone == "Etc/UTC"
    end

    test "converts New York time to UTC (EDT/UTC-4 during daylight saving)" do
      # 8:00 PM EDT (summer) should become 12:00 AM UTC next day
      naive_dt = ~N[2025-07-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "America/New_York")

      assert utc_dt.day == 17
      assert utc_dt.hour == 0
      assert utc_dt.minute == 0
    end

    test "converts Warsaw time to UTC (CET/UTC+1 winter)" do
      # 8:00 PM CET (winter) should become 7:00 PM UTC same day
      naive_dt = ~N[2025-01-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "Europe/Warsaw")

      assert utc_dt.day == 16
      assert utc_dt.hour == 19
      assert utc_dt.minute == 0
    end

    test "converts Warsaw time to UTC (CEST/UTC+2 summer)" do
      # 8:00 PM CEST (summer) should become 6:00 PM UTC same day
      naive_dt = ~N[2025-07-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "Europe/Warsaw")

      assert utc_dt.day == 16
      assert utc_dt.hour == 18
      assert utc_dt.minute == 0
    end

    test "converts Los Angeles time to UTC (PST/UTC-8)" do
      # 8:00 PM PST (winter) should become 4:00 AM UTC next day
      naive_dt = ~N[2025-01-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "America/Los_Angeles")

      assert utc_dt.day == 17
      assert utc_dt.hour == 4
      assert utc_dt.minute == 0
    end

    test "converts Tokyo time to UTC (JST/UTC+9)" do
      # 8:00 PM JST should become 11:00 AM UTC same day
      naive_dt = ~N[2025-01-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "Asia/Tokyo")

      assert utc_dt.day == 16
      assert utc_dt.hour == 11
      assert utc_dt.minute == 0
    end

    test "handles nil timezone by defaulting to UTC" do
      naive_dt = ~N[2025-01-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, nil)

      assert utc_dt.hour == 20
      assert utc_dt.day == 16
      assert utc_dt.time_zone == "Etc/UTC"
    end

    test "handles invalid timezone by falling back to UTC" do
      naive_dt = ~N[2025-01-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "Invalid/Timezone")

      # Should log warning and use UTC
      assert utc_dt.hour == 20
      assert utc_dt.time_zone == "Etc/UTC"
    end

    test "handles midnight conversion correctly" do
      # Midnight in New York should be 5:00 AM UTC (EST)
      naive_dt = ~N[2025-01-16 00:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "America/New_York")

      assert utc_dt.day == 16
      assert utc_dt.hour == 5
      assert utc_dt.minute == 0
    end

    test "handles end of day conversion correctly" do
      # 11:59 PM in New York should be 4:59 AM UTC next day (EST)
      naive_dt = ~N[2025-01-16 23:59:59]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "America/New_York")

      assert utc_dt.day == 17
      assert utc_dt.hour == 4
      assert utc_dt.minute == 59
      assert utc_dt.second == 59
    end
  end

  describe "parse_datetime_with_timezone/2" do
    test "parses ISO8601 datetime with timezone offset" do
      # Already has timezone offset (-05:00 for EST)
      utc_dt =
        TimezoneConverter.parse_datetime_with_timezone(
          "2025-01-16T20:00:00-05:00",
          "America/New_York"
        )

      assert utc_dt.day == 17
      assert utc_dt.hour == 1
      assert utc_dt.time_zone == "Etc/UTC"
    end

    test "parses ISO8601 datetime without timezone using venue timezone" do
      # No timezone offset, use venue timezone
      utc_dt =
        TimezoneConverter.parse_datetime_with_timezone(
          "2025-01-16T20:00:00",
          "Europe/Warsaw"
        )

      assert utc_dt.day == 16
      # 8PM CET = 7PM UTC (winter)
      assert utc_dt.hour == 19
    end

    test "parses date-only string with default time in venue timezone" do
      # Date only, defaults to 8:00 PM in venue timezone
      utc_dt =
        TimezoneConverter.parse_datetime_with_timezone(
          "2025-01-16",
          "America/New_York"
        )

      assert utc_dt.day == 17
      # 8PM EST = 1AM UTC next day
      assert utc_dt.hour == 1
    end

    test "handles nil date string" do
      assert TimezoneConverter.parse_datetime_with_timezone(nil, "America/New_York") == nil
    end

    test "handles invalid date string" do
      assert TimezoneConverter.parse_datetime_with_timezone("invalid", "America/New_York") == nil
    end
  end

  describe "infer_timezone_from_location/2" do
    # NOTE: TzWorld runtime lookups are disabled due to OOM issues (~512MB RAM).
    # This function now always returns UTC as a safe fallback.
    # For accurate timezones, use city.timezone (precomputed during city creation).

    test "returns UTC for all coordinates (TzWorld disabled)" do
      # Since TzWorld is disabled, all coordinates return UTC
      # Scrapers should use city.timezone instead

      # Kraków, Poland
      assert TimezoneConverter.infer_timezone_from_location(50.0647, 19.9450) == "Etc/UTC"

      # Warsaw, Poland
      assert TimezoneConverter.infer_timezone_from_location(52.2297, 21.0122) == "Etc/UTC"

      # New York City
      assert TimezoneConverter.infer_timezone_from_location(40.7128, -74.0060) == "Etc/UTC"

      # Los Angeles
      assert TimezoneConverter.infer_timezone_from_location(34.0522, -118.2437) == "Etc/UTC"

      # Chicago
      assert TimezoneConverter.infer_timezone_from_location(41.8781, -87.6298) == "Etc/UTC"

      # London, UK
      assert TimezoneConverter.infer_timezone_from_location(51.5074, -0.1278) == "Etc/UTC"

      # Paris, France
      assert TimezoneConverter.infer_timezone_from_location(48.8566, 2.3522) == "Etc/UTC"

      # Berlin, Germany
      assert TimezoneConverter.infer_timezone_from_location(52.5200, 13.4050) == "Etc/UTC"

      # Tokyo, Japan
      assert TimezoneConverter.infer_timezone_from_location(35.6762, 139.6503) == "Etc/UTC"

      # Sydney, Australia
      assert TimezoneConverter.infer_timezone_from_location(-33.8688, 151.2093) == "Etc/UTC"
    end

    test "returns UTC for unknown coordinates" do
      # Middle of the ocean
      assert TimezoneConverter.infer_timezone_from_location(0.0, 0.0) == "Etc/UTC"
    end

    test "returns UTC for nil coordinates" do
      assert TimezoneConverter.infer_timezone_from_location(nil, nil) == "Etc/UTC"
      assert TimezoneConverter.infer_timezone_from_location(40.0, nil) == "Etc/UTC"
      assert TimezoneConverter.infer_timezone_from_location(nil, -74.0) == "Etc/UTC"
    end
  end

  describe "timezone_to_city/1" do
    test "maps timezone to city name" do
      assert TimezoneConverter.timezone_to_city("Europe/Warsaw") == {"Warsaw", "Poland"}

      assert TimezoneConverter.timezone_to_city("America/New_York") ==
               {"New York", "United States"}

      assert TimezoneConverter.timezone_to_city("Europe/London") == {"London", "United Kingdom"}
      assert TimezoneConverter.timezone_to_city("Asia/Tokyo") == {"Tokyo", "Japan"}
    end

    test "returns nil for unknown timezones" do
      assert TimezoneConverter.timezone_to_city("Unknown/Timezone") == {nil, nil}
      assert TimezoneConverter.timezone_to_city(nil) == {nil, nil}
    end
  end

  describe "integration scenarios" do
    test "event at 8:00 PM in multiple cities converts correctly to UTC" do
      naive_dt = ~N[2025-01-16 20:00:00]

      # New York (EST/UTC-5)
      ny_utc = TimezoneConverter.convert_local_to_utc(naive_dt, "America/New_York")
      assert {ny_utc.day, ny_utc.hour} == {17, 1}

      # Los Angeles (PST/UTC-8)
      la_utc = TimezoneConverter.convert_local_to_utc(naive_dt, "America/Los_Angeles")
      assert {la_utc.day, la_utc.hour} == {17, 4}

      # Warsaw (CET/UTC+1)
      warsaw_utc = TimezoneConverter.convert_local_to_utc(naive_dt, "Europe/Warsaw")
      assert {warsaw_utc.day, warsaw_utc.hour} == {16, 19}

      # Tokyo (JST/UTC+9)
      tokyo_utc = TimezoneConverter.convert_local_to_utc(naive_dt, "Asia/Tokyo")
      assert {tokyo_utc.day, tokyo_utc.hour} == {16, 11}
    end

    test "coordinates → timezone → UTC conversion chain (with city.timezone)" do
      # NOTE: TzWorld is disabled, so infer_timezone_from_location returns UTC.
      # In production, scrapers use city.timezone (precomputed) for accuracy.
      # This test demonstrates the flow when city.timezone is available.

      # Simulating city.timezone being set (as it would be in production)
      timezone = "Europe/Warsaw"

      # Event at 8:00 PM in Kraków
      naive_dt = ~N[2025-01-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, timezone)

      # 8:00 PM CET = 7:00 PM UTC (winter)
      assert utc_dt.day == 16
      assert utc_dt.hour == 19
    end

    test "coordinates fallback returns UTC (TzWorld disabled)" do
      # When city.timezone is not available, infer_timezone_from_location returns UTC
      timezone = TimezoneConverter.infer_timezone_from_location(50.0647, 19.9450)
      assert timezone == "Etc/UTC"

      # This results in times being interpreted as UTC
      naive_dt = ~N[2025-01-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, timezone)

      # Time stays at 20:00 since it's already treated as UTC
      assert utc_dt.day == 16
      assert utc_dt.hour == 20
    end

    test "round-trip conversion: local → UTC → local" do
      # Start with 8:00 PM in New York
      naive_dt = ~N[2025-01-16 20:00:00]

      # Convert to UTC
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "America/New_York")
      assert utc_dt.hour == 1
      assert utc_dt.day == 17

      # Convert back to New York time (simulating display layer)
      local_dt = DateTime.shift_zone!(utc_dt, "America/New_York")
      assert local_dt.hour == 20
      assert local_dt.day == 16
    end
  end
end
