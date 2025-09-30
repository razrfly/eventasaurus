defmodule EventasaurusDiscovery.Scraping.Helpers.TimezoneConverter do
  @moduledoc """
  Shared timezone conversion utilities for all scrapers.
  Ensures consistent timezone handling across Ticketmaster, Bandsintown, and Karnet.

  ## Purpose

  All events are stored in the database with UTC times. This module provides
  utilities to convert local event times (from various sources/timezones) to UTC
  for consistent storage.

  The display layer then converts UTC times back to local timezone for presentation.

  ## Usage

      # Convert a naive datetime from a specific timezone to UTC
      naive_dt = ~N[2025-10-16 20:00:00]
      utc_dt = TimezoneConverter.convert_local_to_utc(naive_dt, "America/New_York")

      # Parse a datetime string with timezone context
      utc_dt = TimezoneConverter.parse_datetime_with_timezone(
        "2025-10-16T20:00:00",
        "Europe/Warsaw"
      )

      # Infer timezone from coordinates
      timezone = TimezoneConverter.infer_timezone_from_location(50.0647, 19.9450)
      # => "Europe/Warsaw"
  """

  require Logger

  @doc """
  Converts a naive datetime (no timezone) from a local timezone to UTC for storage.

  This is the core function used by all scrapers to ensure times are stored
  consistently in UTC.

  ## Examples

      # Event at 8:00 PM in New York (EST/UTC-5)
      iex> naive_dt = ~N[2025-10-16 20:00:00]
      iex> convert_local_to_utc(naive_dt, "America/New_York")
      #DateTime<2025-10-17 01:00:00Z>  # Next day, 1:00 AM UTC

      # Event at 8:00 PM in Warsaw (CEST/UTC+2)
      iex> naive_dt = ~N[2025-10-16 20:00:00]
      iex> convert_local_to_utc(naive_dt, "Europe/Warsaw")
      #DateTime<2025-10-16 18:00:00Z>  # Same day, 6:00 PM UTC

      # No timezone provided - defaults to UTC
      iex> naive_dt = ~N[2025-10-16 20:00:00]
      iex> convert_local_to_utc(naive_dt, nil)
      #DateTime<2025-10-16 20:00:00Z>
  """
  def convert_local_to_utc(naive_datetime, timezone) when is_binary(timezone) do
    case Timex.to_datetime(naive_datetime, timezone) do
      {:error, reason} ->
        Logger.warning(
          "Could not convert to timezone: #{timezone}, falling back to UTC. Reason: #{inspect(reason)}"
        )

        DateTime.from_naive!(naive_datetime, "Etc/UTC")

      %DateTime{} = dt ->
        # Convert to UTC for storage
        Timex.to_datetime(dt, "Etc/UTC")

      _ ->
        Logger.warning("Unexpected result from timezone conversion for timezone: #{timezone}")
        DateTime.from_naive!(naive_datetime, "Etc/UTC")
    end
  end

  def convert_local_to_utc(naive_datetime, nil) do
    Logger.warning("No timezone provided, assuming UTC")
    DateTime.from_naive!(naive_datetime, "Etc/UTC")
  end

  @doc """
  Parses a datetime string and converts to UTC using the provided timezone.

  Handles both ISO8601 strings with timezone offsets and naive datetime strings.
  This is useful when the source data may or may not include timezone information.

  ## Examples

      # Already has timezone offset - use it
      iex> parse_datetime_with_timezone("2025-10-16T20:00:00-05:00", "America/New_York")
      #DateTime<2025-10-17 01:00:00Z>

      # No timezone - use provided timezone
      iex> parse_datetime_with_timezone("2025-10-16T20:00:00", "Europe/Warsaw")
      #DateTime<2025-10-16 18:00:00Z>

      # Date only - defaults to 8:00 PM in venue timezone
      iex> parse_datetime_with_timezone("2025-10-16", "Europe/Warsaw")
      #DateTime<2025-10-16 18:00:00Z>  # 8PM Warsaw = 6PM UTC
  """
  def parse_datetime_with_timezone(datetime_string, venue_timezone)
      when is_binary(datetime_string) do
    cond do
      # Check if it's already a valid datetime with timezone offset
      String.contains?(datetime_string, "T") ->
        case DateTime.from_iso8601(datetime_string) do
          {:ok, datetime, _offset} ->
            # Already has timezone, convert to UTC
            DateTime.shift_zone!(datetime, "Etc/UTC")

          {:error, :missing_offset} ->
            # Parse as local time in venue timezone
            parse_as_local_time(datetime_string, venue_timezone)

          _ ->
            Logger.warning("Could not parse datetime: #{datetime_string}")
            nil
        end

      # Date-only string (no time component)
      true ->
        case Date.from_iso8601(datetime_string) do
          {:ok, date} ->
            # Default to 8 PM in the venue's timezone
            time = ~T[20:00:00]
            timezone = venue_timezone || "Etc/UTC"

            naive_datetime = NaiveDateTime.new!(date, time)
            convert_local_to_utc(naive_datetime, timezone)

          _ ->
            Logger.warning("Could not parse date: #{datetime_string}")
            nil
        end
    end
  end

  def parse_datetime_with_timezone(nil, _venue_timezone), do: nil

  defp parse_as_local_time(datetime_string, venue_timezone) do
    timezone = venue_timezone || "Etc/UTC"

    with {:ok, naive_dt} <- NaiveDateTime.from_iso8601(datetime_string) do
      convert_local_to_utc(naive_dt, timezone)
    else
      _ ->
        Logger.warning(
          "Could not parse local datetime: #{datetime_string} with timezone: #{timezone}"
        )

        nil
    end
  end

  @doc """
  Infers timezone from venue location coordinates.

  This is a simplified implementation using coordinate ranges. In a production
  system, this should be replaced with a proper geo-to-timezone database
  (such as tzdata, GeoNames, or a similar service).

  ## Examples

      # Kraków, Poland
      iex> infer_timezone_from_location(50.0647, 19.9450)
      "Europe/Warsaw"

      # New York, USA
      iex> infer_timezone_from_location(40.7128, -74.0060)
      "America/New_York"

      # Los Angeles, USA
      iex> infer_timezone_from_location(34.0522, -118.2437)
      "America/Los_Angeles"

      # Unknown location
      iex> infer_timezone_from_location(0.0, 0.0)
      "Etc/UTC"

  ## Future Enhancement

  Consider integrating with:
  - [tz_world](https://hex.pm/packages/tz_world) for accurate timezone lookup
  - [geo_timezone](https://hex.pm/packages/geo_timezone) for coordinate-based detection
  - Google Maps Timezone API for production-grade accuracy
  """
  def infer_timezone_from_location(latitude, longitude)
      when not is_nil(latitude) and not is_nil(longitude) do
    cond do
      # Poland (approximate bounding box)
      # Covers most of Poland including Warsaw, Kraków, Gdańsk
      latitude >= 49.0 and latitude <= 55.0 and longitude >= 14.0 and longitude <= 24.5 ->
        "Europe/Warsaw"

      # Eastern USA (approximate)
      # Covers NYC, Boston, Philadelphia, Washington DC, Miami
      latitude >= 24.0 and latitude <= 50.0 and longitude >= -85.0 and longitude <= -65.0 ->
        "America/New_York"

      # Central USA (approximate)
      # Covers Chicago, Dallas, Houston
      latitude >= 25.0 and latitude <= 50.0 and longitude >= -105.0 and longitude <= -85.0 ->
        "America/Chicago"

      # Mountain USA (approximate)
      # Covers Denver, Phoenix, Salt Lake City
      latitude >= 30.0 and latitude <= 50.0 and longitude >= -115.0 and longitude <= -105.0 ->
        "America/Denver"

      # Western USA (approximate)
      # Covers Los Angeles, San Francisco, Seattle, Portland
      latitude >= 30.0 and latitude <= 50.0 and longitude >= -125.0 and longitude <= -115.0 ->
        "America/Los_Angeles"

      # UK (approximate)
      # Covers London, Manchester, Edinburgh
      latitude >= 50.0 and latitude <= 60.0 and longitude >= -8.0 and longitude <= 2.0 ->
        "Europe/London"

      # France (approximate)
      # Covers Paris and most of France
      latitude >= 42.0 and latitude <= 51.0 and longitude >= -5.0 and longitude <= 8.0 ->
        "Europe/Paris"

      # Germany (approximate)
      # Covers Berlin, Munich, Hamburg
      latitude >= 47.0 and latitude <= 55.0 and longitude >= 6.0 and longitude <= 15.0 ->
        "Europe/Berlin"

      # Spain (approximate)
      # Covers Madrid, Barcelona
      latitude >= 36.0 and latitude <= 44.0 and longitude >= -10.0 and longitude <= 4.0 ->
        "Europe/Madrid"

      # Italy (approximate)
      # Covers Rome, Milan, Venice
      latitude >= 36.0 and latitude <= 47.0 and longitude >= 6.0 and longitude <= 19.0 ->
        "Europe/Rome"

      # Japan (approximate)
      # Covers Tokyo, Osaka, Kyoto
      latitude >= 30.0 and latitude <= 46.0 and longitude >= 129.0 and longitude <= 146.0 ->
        "Asia/Tokyo"

      # Australia - Sydney (approximate)
      # Covers Sydney, Melbourne
      latitude >= -38.0 and latitude <= -28.0 and longitude >= 144.0 and longitude <= 154.0 ->
        "Australia/Sydney"

      # Central Europe (default for European coordinates not matched above)
      latitude >= 35.0 and latitude <= 71.0 and longitude >= -10.0 and longitude <= 40.0 ->
        "Europe/Warsaw"

      # Default to UTC for unknown locations
      true ->
        Logger.info(
          "Unknown timezone for coordinates (#{latitude}, #{longitude}), using UTC"
        )

        "Etc/UTC"
    end
  end

  def infer_timezone_from_location(_, _), do: "Etc/UTC"

  @doc """
  Maps a timezone string to a city name (for display purposes).

  This is the inverse of infer_timezone_from_location and is useful
  for displaying human-readable location information.

  ## Examples

      iex> timezone_to_city("Europe/Warsaw")
      {"Warsaw", "Poland"}

      iex> timezone_to_city("America/New_York")
      {"New York", "United States"}
  """
  def timezone_to_city(nil), do: {nil, nil}

  def timezone_to_city(timezone) do
    case timezone do
      "Europe/Warsaw" -> {"Warsaw", "Poland"}
      "Europe/London" -> {"London", "United Kingdom"}
      "Europe/Paris" -> {"Paris", "France"}
      "Europe/Berlin" -> {"Berlin", "Germany"}
      "Europe/Madrid" -> {"Madrid", "Spain"}
      "Europe/Rome" -> {"Rome", "Italy"}
      "America/New_York" -> {"New York", "United States"}
      "America/Chicago" -> {"Chicago", "United States"}
      "America/Denver" -> {"Denver", "United States"}
      "America/Los_Angeles" -> {"Los Angeles", "United States"}
      "Asia/Tokyo" -> {"Tokyo", "Japan"}
      "Australia/Sydney" -> {"Sydney", "Australia"}
      _ -> {nil, nil}
    end
  end
end