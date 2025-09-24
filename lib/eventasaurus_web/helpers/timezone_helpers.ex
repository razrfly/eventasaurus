defmodule EventasaurusWeb.TimezoneHelpers do
  @moduledoc """
  Helper functions for working with timezones in the application.
  """

  # Cache the timezone options to avoid recalculating on each request
  # Recalculate every 24 hours to account for potential DST changes
  @timezone_cache_ttl :timer.hours(24)

  @doc """
  Returns a categorized list of timezone options for select inputs.
  Each timezone includes the city name and the UTC offset.
  """
  def timezone_options do
    # Use process dictionary as a simple cache
    current_time = System.system_time(:second)
    cache_expiry = current_time - @timezone_cache_ttl

    case Process.get({__MODULE__, :categorized_options}) do
      {timestamp, options} when timestamp > cache_expiry ->
        options

      _ ->
        options = [
          {"Americas", americas_options()},
          {"Europe & Africa", europe_africa_options()},
          {"Asia & Pacific", asia_pacific_options()}
        ]

        Process.put({__MODULE__, :categorized_options}, {current_time, options})
        options
    end
  end

  @doc """
  Returns a flat list of all timezone options suitable for select inputs.
  """
  def all_timezone_options do
    # Use process dictionary as a simple cache
    current_time = System.system_time(:second)
    cache_expiry = current_time - @timezone_cache_ttl

    case Process.get({__MODULE__, :all_options}) do
      {timestamp, options} when timestamp > cache_expiry ->
        options

      _ ->
        options =
          TimeZoneInfo.time_zones()
          |> Enum.map(fn tz ->
            formatted = format_timezone_option(tz)
            {formatted, tz}
          end)
          |> Enum.sort_by(fn {formatted, _} -> formatted end)

        Process.put({__MODULE__, :all_options}, {current_time, options})
        options
    end
  end

  @doc """
  Convert a UTC datetime to the specified timezone.
  Returns the converted datetime or the original if conversion fails.
  """
  def convert_to_timezone(datetime, timezone) when is_binary(timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, converted} -> converted
      {:error, _} -> datetime
    end
  end

  def convert_to_timezone(datetime, _), do: datetime

  @doc """
  Format a timezone string with its UTC offset for display purposes.
  Example: "America/New_York (UTC-05:00)"
  """
  def format_timezone_option(timezone) do
    now = DateTime.utc_now()

    with {:ok, datetime} <- DateTime.shift_zone(now, timezone),
         offset_seconds <- datetime.utc_offset + datetime.std_offset,
         offset_hours <- div(offset_seconds, 3600),
         offset_minutes <- div(rem(offset_seconds, 3600), 60) do
      # Format city name more nicely (replace _ with spaces)
      city =
        timezone
        |> String.split("/")
        |> List.last()
        |> String.replace("_", " ")

      # Format UTC offset
      sign = if offset_seconds >= 0, do: "+", else: "-"

      offset_string =
        "#{sign}#{String.pad_leading("#{abs(offset_hours)}", 2, "0")}:#{String.pad_leading("#{abs(offset_minutes)}", 2, "0")}"

      "#{city} (UTC#{offset_string})"
    else
      # Fallback to just the timezone name if anything fails
      _ -> timezone
    end
  end

  # Common timezones for Americas region
  defp americas_options do
    [
      "America/New_York",
      "America/Chicago",
      "America/Denver",
      "America/Los_Angeles",
      "America/Mexico_City",
      "America/Toronto",
      "America/Vancouver",
      "America/Sao_Paulo",
      "America/Argentina/Buenos_Aires",
      "America/Bogota",
      "America/Santiago",
      "America/Lima",
      "America/Montreal"
    ]
    |> Enum.map(fn tz ->
      {format_timezone_option(tz), tz}
    end)
  end

  # Common timezones for Europe and Africa
  defp europe_africa_options do
    [
      "Europe/London",
      "Europe/Warsaw",
      "Europe/Paris",
      "Europe/Berlin",
      "Europe/Rome",
      "Europe/Madrid",
      "Europe/Amsterdam",
      "Europe/Vienna",
      "Europe/Prague",
      "Europe/Stockholm",
      "Europe/Zurich",
      "Europe/Dublin",
      "Europe/Brussels",
      "Europe/Kiev",
      "Europe/Istanbul",
      "Europe/Athens",
      "Africa/Cairo",
      "Africa/Johannesburg",
      "Africa/Lagos",
      "Africa/Nairobi",
      "Europe/Moscow"
    ]
    |> Enum.map(fn tz ->
      {format_timezone_option(tz), tz}
    end)
  end

  # Common timezones for Asia and Pacific
  defp asia_pacific_options do
    [
      "Asia/Tokyo",
      # Also Beijing
      "Asia/Shanghai",
      "Asia/Singapore",
      "Asia/Seoul",
      "Australia/Sydney",
      "Australia/Melbourne",
      "Pacific/Auckland",
      "Asia/Dubai",
      # Also New Delhi
      "Asia/Kolkata",
      "Asia/Bangkok",
      "Asia/Jakarta",
      "Asia/Kuala_Lumpur",
      "Asia/Manila",
      "Asia/Taipei",
      "Asia/Hong_Kong",
      "Asia/Karachi"
    ]
    |> Enum.map(fn tz ->
      {format_timezone_option(tz), tz}
    end)
  end
end
