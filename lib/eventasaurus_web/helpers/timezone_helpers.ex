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
      {"Sao Paulo (UTC-03:00)", "America/Sao_Paulo"},
      {"Buenos Aires (UTC-03:00)", "America/Argentina/Buenos_Aires"},
      {"Bogota (UTC-05:00)", "America/Bogota"},
      {"Santiago (UTC-04:00)", "America/Santiago"},
      {"Lima (UTC-05:00)", "America/Lima"},
      {"Montreal (UTC-05:00)", "America/Montreal"}
    ]
  end

  # Common timezones for Europe and Africa
  defp europe_africa_options do
    [
      {"London (UTC+00:00)", "Europe/London"},
      {"Warsaw (UTC+01:00)", "Europe/Warsaw"},
      {"Paris (UTC+01:00)", "Europe/Paris"},
      {"Berlin (UTC+01:00)", "Europe/Berlin"},
      {"Rome (UTC+01:00)", "Europe/Rome"},
      {"Madrid (UTC+01:00)", "Europe/Madrid"},
      {"Amsterdam (UTC+01:00)", "Europe/Amsterdam"},
      {"Vienna (UTC+01:00)", "Europe/Vienna"},
      {"Prague (UTC+01:00)", "Europe/Prague"},
      {"Stockholm (UTC+01:00)", "Europe/Stockholm"},
      {"Zurich (UTC+01:00)", "Europe/Zurich"},
      {"Dublin (UTC+00:00)", "Europe/Dublin"},
      {"Brussels (UTC+01:00)", "Europe/Brussels"},
      {"Kiev (UTC+02:00)", "Europe/Kiev"},
      {"Istanbul (UTC+03:00)", "Europe/Istanbul"},
      {"Athens (UTC+02:00)", "Europe/Athens"},
      {"Cairo (UTC+02:00)", "Africa/Cairo"},
      {"Johannesburg (UTC+02:00)", "Africa/Johannesburg"},
      {"Lagos (UTC+01:00)", "Africa/Lagos"},
      {"Nairobi (UTC+03:00)", "Africa/Nairobi"},
      {"Moscow (UTC+03:00)", "Europe/Moscow"}
    ]
  end

  # Common timezones for Asia and Pacific
  defp asia_pacific_options do
    [
      {"Tokyo (UTC+09:00)", "Asia/Tokyo"},
      {"Shanghai (UTC+08:00)", "Asia/Shanghai"},
      {"Singapore (UTC+08:00)", "Asia/Singapore"},
      {"Seoul (UTC+09:00)", "Asia/Seoul"},
      {"Sydney (UTC+10:00)", "Australia/Sydney"},
      {"Melbourne (UTC+10:00)", "Australia/Melbourne"},
      {"Auckland (UTC+12:00)", "Pacific/Auckland"},
      {"Dubai (UTC+04:00)", "Asia/Dubai"},
      {"Mumbai (UTC+05:30)", "Asia/Kolkata"},
      {"New Delhi (UTC+05:30)", "Asia/Kolkata"},
      {"Bangkok (UTC+07:00)", "Asia/Bangkok"},
      {"Jakarta (UTC+07:00)", "Asia/Jakarta"},
      {"Kuala Lumpur (UTC+08:00)", "Asia/Kuala_Lumpur"},
      {"Manila (UTC+08:00)", "Asia/Manila"},
      {"Taipei (UTC+08:00)", "Asia/Taipei"},
      {"Hong Kong (UTC+08:00)", "Asia/Hong_Kong"},
      {"Beijing (UTC+08:00)", "Asia/Shanghai"},
      {"Karachi (UTC+05:00)", "Asia/Karachi"}
    ]
  end
end
