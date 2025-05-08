defmodule EventasaurusWeb.TimezoneHelpers do
  @moduledoc """
  Helper functions for working with timezones in the application.
  """

  @doc """
  Returns a categorized list of timezone options for select inputs.
  Each timezone includes the city name and the UTC offset.
  """
  def timezone_options do
    [
      {"Americas", americas_options()},
      {"Europe & Africa", europe_africa_options()},
      {"Asia & Pacific", asia_pacific_options()}
    ]
  end

  @doc """
  Returns a flat list of all timezone options suitable for select inputs.
  """
  def all_timezone_options do
    timezone_map =
      TimeZoneInfo.time_zones()
      |> Enum.map(fn tz ->
        formatted = format_timezone_option(tz)
        {formatted, tz}
      end)
      |> Enum.sort_by(fn {formatted, _} -> formatted end)

    timezone_map
  end

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
      city = timezone
             |> String.split("/")
             |> List.last()
             |> String.replace("_", " ")

      # Format UTC offset
      sign = if offset_seconds >= 0, do: "+", else: "-"
      offset_string = "#{sign}#{String.pad_leading("#{abs(offset_hours)}", 2, "0")}:#{String.pad_leading("#{abs(offset_minutes)}", 2, "0")}"

      "#{city} (UTC#{offset_string})"
    else
      _ -> timezone # Fallback to just the timezone name if anything fails
    end
  end

  # Common timezones for Americas region
  defp americas_options do
    [
      {"New York (UTC-05:00)", "America/New_York"},
      {"Chicago (UTC-06:00)", "America/Chicago"},
      {"Denver (UTC-07:00)", "America/Denver"},
      {"Los Angeles (UTC-08:00)", "America/Los_Angeles"},
      {"Mexico City (UTC-06:00)", "America/Mexico_City"},
      {"Toronto (UTC-05:00)", "America/Toronto"},
      {"Vancouver (UTC-08:00)", "America/Vancouver"},
      {"Sao Paulo (UTC-03:00)", "America/Sao_Paulo"}
    ]
  end

  # Common timezones for Europe and Africa
  defp europe_africa_options do
    [
      {"London (UTC+00:00)", "Europe/London"},
      {"Paris (UTC+01:00)", "Europe/Paris"},
      {"Berlin (UTC+01:00)", "Europe/Berlin"},
      {"Rome (UTC+01:00)", "Europe/Rome"},
      {"Madrid (UTC+01:00)", "Europe/Madrid"},
      {"Amsterdam (UTC+01:00)", "Europe/Amsterdam"},
      {"Cairo (UTC+02:00)", "Africa/Cairo"},
      {"Johannesburg (UTC+02:00)", "Africa/Johannesburg"},
      {"Moscow (UTC+03:00)", "Europe/Moscow"}
    ]
  end

  # Common timezones for Asia and Pacific
  defp asia_pacific_options do
    [
      {"Tokyo (UTC+09:00)", "Asia/Tokyo"},
      {"Shanghai (UTC+08:00)", "Asia/Shanghai"},
      {"Singapore (UTC+08:00)", "Asia/Singapore"},
      {"Sydney (UTC+10:00)", "Australia/Sydney"},
      {"Auckland (UTC+12:00)", "Pacific/Auckland"},
      {"Dubai (UTC+04:00)", "Asia/Dubai"},
      {"Mumbai (UTC+05:30)", "Asia/Kolkata"},
      {"Hong Kong (UTC+08:00)", "Asia/Hong_Kong"}
    ]
  end
end
