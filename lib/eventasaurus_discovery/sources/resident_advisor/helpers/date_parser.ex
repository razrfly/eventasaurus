defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Helpers.DateParser do
  @moduledoc """
  Parses Resident Advisor date and time formats into UTC DateTimes.

  RA provides dates as ISO strings and times as strings (e.g., "23:00").
  These need to be combined and converted to UTC based on venue timezone.
  """

  require Logger

  @doc """
  Parse RA date and start time into a UTC DateTime.

  ## Parameters
  - `date_str` - ISO date string (e.g., "2025-10-15")
  - `time_str` - Time string (e.g., "23:00" or "23:00:00")
  - `timezone` - Venue timezone (e.g., "Europe/Warsaw")

  ## Returns
  - `DateTime` in UTC
  - `nil` if parsing fails

  ## Examples

      iex> DateParser.parse_start_datetime("2025-10-15", "23:00", "Europe/Warsaw")
      ~U[2025-10-15 21:00:00Z]
  """
  def parse_start_datetime(date_str, time_str, timezone \\ "Etc/UTC")

  def parse_start_datetime(nil, _, _), do: nil

  # IMPORTANT: Fallback for nil time MUST come before the string match
  # Otherwise events without startTime get nil instead of 20:00 default
  def parse_start_datetime(date_str, nil, timezone) when is_binary(date_str) do
    # If no time provided, default to 20:00 (common event start time)
    parse_start_datetime(date_str, "20:00", timezone)
  end

  def parse_start_datetime(date_str, time_str, timezone)
      when is_binary(date_str) and is_binary(time_str) do
    # RA can provide dates as "2025-10-31" or "2025-10-31T00:00:00.000"
    # Extract just the date part if ISO datetime format
    date_only = extract_date_part(date_str)
    time_only = extract_time_part(time_str)

    with {:ok, date} <- Date.from_iso8601(date_only),
         {:ok, time} <- parse_time_string(time_only),
         {:ok, naive_dt} <- NaiveDateTime.new(date, time),
         {:ok, local_dt} <- DateTime.from_naive(naive_dt, timezone) do
      DateTime.shift_zone!(local_dt, "Etc/UTC")
    else
      {:error, reason} ->
        Logger.warning("""
        ⚠️ Failed to parse RA datetime
        Date: #{date_str}
        Time: #{time_str}
        Timezone: #{timezone}
        Reason: #{inspect(reason)}
        """)

        nil
    end
  end

  @doc """
  Parse RA end time into a UTC DateTime.

  ## Parameters
  - `date_str` - ISO date string (e.g., "2025-10-15")
  - `end_time_str` - End time string (e.g., "04:00")
  - `start_datetime` - Already parsed start DateTime (for date rollover detection)
  - `timezone` - Venue timezone

  ## Returns
  - `DateTime` in UTC
  - `nil` if parsing fails or no end time

  ## Examples

      iex> start = ~U[2025-10-15 21:00:00Z]
      iex> DateParser.parse_end_datetime("2025-10-15", "04:00", start, "Europe/Warsaw")
      ~U[2025-10-16 02:00:00Z]  # Next day
  """
  def parse_end_datetime(date_str, end_time_str, start_datetime, timezone)

  def parse_end_datetime(nil, _, _, _), do: nil
  def parse_end_datetime(_, nil, _, _), do: nil
  def parse_end_datetime(_, _, nil, _), do: nil

  def parse_end_datetime(date_str, end_time_str, start_datetime, timezone)
      when is_binary(date_str) and is_binary(end_time_str) do
    # Extract date and time parts (handle ISO datetime format)
    date_only = extract_date_part(date_str)
    time_only = extract_time_part(end_time_str)

    with {:ok, date} <- Date.from_iso8601(date_only),
         {:ok, end_time} <- parse_time_string(time_only),
         {:ok, naive_dt} <- NaiveDateTime.new(date, end_time),
         {:ok, local_dt} <- DateTime.from_naive(naive_dt, timezone) do
      end_utc = DateTime.shift_zone!(local_dt, "Etc/UTC")

      # Check if end time is before start time (indicates next day)
      if DateTime.compare(end_utc, start_datetime) == :lt do
        # Add one day to end time
        DateTime.add(end_utc, 86400, :second)
      else
        end_utc
      end
    else
      {:error, reason} ->
        Logger.warning("""
        ⚠️ Failed to parse RA end datetime
        Date: #{date_str}
        End Time: #{end_time_str}
        Timezone: #{timezone}
        Reason: #{inspect(reason)}
        """)

        nil
    end
  end

  @doc """
  Get timezone from city, preferring precomputed timezone over coordinate lookup.

  Uses this priority:
  1. `city.timezone` - precomputed, preferred
  2. Coordinate lookup (currently returns UTC as fallback)

  ## Parameters
  - `city` - City struct with optional timezone and lat/lng

  ## Returns
  - Timezone string (e.g., "Europe/Warsaw")
  """
  def infer_timezone(city) do
    # Prefer precomputed city timezone (most accurate, no runtime overhead)
    cond do
      is_binary(city.timezone) && city.timezone != "" ->
        city.timezone

      city.latitude && city.longitude ->
        # Fallback to coordinate lookup (returns UTC since TzWorld is disabled)
        lat =
          if is_struct(city.latitude, Decimal),
            do: Decimal.to_float(city.latitude),
            else: city.latitude

        lng =
          if is_struct(city.longitude, Decimal),
            do: Decimal.to_float(city.longitude),
            else: city.longitude

        EventasaurusDiscovery.Scraping.Helpers.TimezoneConverter.infer_timezone_from_location(
          lat,
          lng
        )

      true ->
        "Etc/UTC"
    end
  end

  # Private functions

  defp extract_date_part(datetime_str) do
    # Extract date from "2025-10-31" or "2025-10-31T00:00:00.000"
    case String.split(datetime_str, "T") do
      [date_part | _] -> date_part
      _ -> datetime_str
    end
  end

  defp extract_time_part(datetime_str) do
    # Extract time from "22:00:00" or "2025-10-31T22:00:00.000"
    case String.split(datetime_str, "T") do
      [_, time_part] ->
        # Remove milliseconds if present
        time_part
        |> String.split(".")
        |> hd()

      _ ->
        # Already just a time string
        datetime_str
    end
  end

  defp parse_time_string(time_str) do
    # Handle formats: "23:00", "23:00:00", "9:00", "09:00"
    case String.split(time_str, ":") do
      [hour, minute] ->
        with {h, ""} <- Integer.parse(hour),
             {m, ""} <- Integer.parse(minute) do
          Time.new(h, m, 0)
        else
          _ -> {:error, :invalid_time_format}
        end

      [hour, minute, second] ->
        with {h, ""} <- Integer.parse(hour),
             {m, ""} <- Integer.parse(minute),
             {s, ""} <- Integer.parse(second) do
          Time.new(h, m, s)
        else
          _ -> {:error, :invalid_time_format}
        end

      _ ->
        {:error, :invalid_time_format}
    end
  end
end
