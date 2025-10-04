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
  Infers timezone from venue location coordinates using TzWorld.

  Uses the IANA timezone boundary database to accurately determine timezone
  from latitude/longitude coordinates. Covers all 400+ timezones worldwide.

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

      # Coordinates in ocean (no timezone)
      iex> infer_timezone_from_location(0.0, 0.0)
      "Etc/UTC"

      # Nil coordinates
      iex> infer_timezone_from_location(nil, nil)
      "Etc/UTC"
  """
  def infer_timezone_from_location(latitude, longitude)
      when not is_nil(latitude) and not is_nil(longitude) do
    # TzWorld expects {longitude, latitude} tuple
    case TzWorld.timezone_at({longitude, latitude}) do
      {:ok, timezone} ->
        timezone

      {:error, :time_zone_not_found} ->
        Logger.info("No timezone found for coordinates (#{latitude}, #{longitude}), using UTC")

        "Etc/UTC"

      {:error, :enoent} ->
        Logger.warning(
          "TzWorld data file not found, using UTC for coordinates (#{latitude}, #{longitude})"
        )

        "Etc/UTC"

      {:error, reason} ->
        Logger.warning(
          "TzWorld error #{inspect(reason)} for coordinates (#{latitude}, #{longitude}), using UTC"
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
