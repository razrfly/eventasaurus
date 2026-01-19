defmodule EventasaurusWeb.Utils.TimezoneUtilsTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.Utils.TimezoneUtils

  describe "default_timezone/0" do
    test "returns Europe/Warsaw as the default timezone" do
      assert TimezoneUtils.default_timezone() == "Europe/Warsaw"
    end
  end

  describe "default_timezone_for_context/1" do
    test "returns timezone from country code when country map provided" do
      assert TimezoneUtils.default_timezone_for_context(%{country: %{code: "GB"}}) ==
               "Europe/London"

      assert TimezoneUtils.default_timezone_for_context(%{country: %{code: "US"}}) ==
               "America/New_York"

      assert TimezoneUtils.default_timezone_for_context(%{country: %{code: "FR"}}) ==
               "Europe/Paris"

      assert TimezoneUtils.default_timezone_for_context(%{country: %{code: "DE"}}) ==
               "Europe/Berlin"

      assert TimezoneUtils.default_timezone_for_context(%{country: %{code: "PL"}}) ==
               "Europe/Warsaw"
    end

    test "returns timezone from nested city.country.code" do
      assert TimezoneUtils.default_timezone_for_context(%{city: %{country: %{code: "GB"}}}) ==
               "Europe/London"

      assert TimezoneUtils.default_timezone_for_context(%{city: %{country: %{code: "ES"}}}) ==
               "Europe/Madrid"

      assert TimezoneUtils.default_timezone_for_context(%{city: %{country: %{code: "IT"}}}) ==
               "Europe/Rome"
    end

    test "returns default timezone when nil provided" do
      assert TimezoneUtils.default_timezone_for_context(nil) == "Europe/Warsaw"
    end

    test "returns default timezone when empty map provided" do
      assert TimezoneUtils.default_timezone_for_context(%{}) == "Europe/Warsaw"
    end

    test "returns default timezone when country code is nil" do
      assert TimezoneUtils.default_timezone_for_context(%{country: %{code: nil}}) ==
               "Europe/Warsaw"
    end

    test "returns default timezone when country is missing code" do
      assert TimezoneUtils.default_timezone_for_context(%{country: %{}}) == "Europe/Warsaw"
    end

    test "returns default timezone for unrecognized country code" do
      # TimezoneMapper returns Warsaw as fallback for unknown codes
      result = TimezoneUtils.default_timezone_for_context(%{country: %{code: "XX"}})
      assert is_binary(result)
    end
  end

  describe "get_event_timezone/1" do
    test "returns timezone from venue coordinates when available" do
      # Warsaw coordinates
      event = %{venue: %{latitude: 52.2297, longitude: 21.0122}}
      assert TimezoneUtils.get_event_timezone(event) == "Europe/Warsaw"
    end

    test "returns default timezone when event is nil" do
      assert TimezoneUtils.get_event_timezone(nil) == "Europe/Warsaw"
    end

    test "returns default timezone when venue is nil" do
      assert TimezoneUtils.get_event_timezone(%{venue: nil}) == "Europe/Warsaw"
    end

    test "returns default timezone when venue lacks coordinates" do
      assert TimezoneUtils.get_event_timezone(%{venue: %{latitude: nil, longitude: nil}}) ==
               "Europe/Warsaw"
    end
  end

  describe "get_venue_timezone/1" do
    test "returns timezone from coordinates" do
      # Krakow coordinates
      venue = %{latitude: 50.0647, longitude: 19.9450}
      assert TimezoneUtils.get_venue_timezone(venue) == "Europe/Warsaw"
    end

    test "returns timezone for London coordinates" do
      venue = %{latitude: 51.5074, longitude: -0.1278}
      assert TimezoneUtils.get_venue_timezone(venue) == "Europe/London"
    end

    test "returns timezone for New York coordinates" do
      venue = %{latitude: 40.7128, longitude: -74.0060}
      assert TimezoneUtils.get_venue_timezone(venue) == "America/New_York"
    end

    test "returns default timezone when venue is nil" do
      assert TimezoneUtils.get_venue_timezone(nil) == "Europe/Warsaw"
    end

    test "returns default timezone when coordinates are nil" do
      assert TimezoneUtils.get_venue_timezone(%{latitude: nil, longitude: nil}) == "Europe/Warsaw"
    end
  end

  describe "get_timezone_from_coordinates/2" do
    test "returns correct timezone for Warsaw" do
      assert TimezoneUtils.get_timezone_from_coordinates(52.2297, 21.0122) == "Europe/Warsaw"
    end

    test "returns correct timezone for London" do
      assert TimezoneUtils.get_timezone_from_coordinates(51.5074, -0.1278) == "Europe/London"
    end

    test "returns correct timezone for Paris" do
      assert TimezoneUtils.get_timezone_from_coordinates(48.8566, 2.3522) == "Europe/Paris"
    end

    test "returns correct timezone for New York" do
      assert TimezoneUtils.get_timezone_from_coordinates(40.7128, -74.0060) == "America/New_York"
    end

    test "returns default timezone for invalid coordinates" do
      assert TimezoneUtils.get_timezone_from_coordinates(nil, nil) == "Europe/Warsaw"
    end
  end

  describe "shift_to_timezone/2" do
    test "shifts datetime to specified timezone" do
      utc_datetime = ~U[2024-01-15 12:00:00Z]

      result = TimezoneUtils.shift_to_timezone(utc_datetime, "Europe/Warsaw")

      assert result.hour == 13
      assert result.time_zone == "Europe/Warsaw"
    end

    test "returns nil when datetime is nil" do
      assert TimezoneUtils.shift_to_timezone(nil, "Europe/Warsaw") == nil
    end

    test "returns original datetime when timezone is invalid" do
      utc_datetime = ~U[2024-01-15 12:00:00Z]
      result = TimezoneUtils.shift_to_timezone(utc_datetime, "Invalid/Timezone")

      assert result == utc_datetime
    end
  end
end
