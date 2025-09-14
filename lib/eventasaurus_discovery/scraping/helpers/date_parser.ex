defmodule EventasaurusDiscovery.Scraping.Helpers.DateParser do
  @moduledoc """
  Utilities for parsing various date and time formats from scraped data.

  Uses Timex library for robust date parsing instead of manual regex patterns.
  """

  require Logger

  @doc """
  Parses a date/time string into a DateTime struct.
  Handles various common formats from event websites using Timex.
  """
  def parse_datetime(nil), do: nil
  def parse_datetime(%DateTime{} = dt), do: dt

  def parse_datetime(string) when is_binary(string) do
    string = String.trim(string)

    # Define common date formats we encounter in scraped data
    # Timex will try each format until one succeeds
    formats = [
      # ISO 8601 formats
      "{ISO:Extended}",                           # 2024-12-25T10:30:00Z
      "{ISO:Extended:Z}",                         # 2024-12-25T10:30:00+00:00
      "{YYYY}-{0M}-{0D}T{h24}:{m}:{s}",          # 2024-12-25T10:30:00
      "{YYYY}-{0M}-{0D} {h24}:{m}:{s}",          # 2024-12-25 10:30:00
      "{YYYY}-{0M}-{0D}",                        # 2024-12-25

      # American formats
      "{M}/{D}/{YYYY} {h12}:{m} {AM}",           # 12/25/2024 10:30 AM
      "{M}/{D}/{YYYY} {h24}:{m}",                # 12/25/2024 22:30
      "{M}/{D}/{YYYY}",                           # 12/25/2024
      "{0M}/{0D}/{YYYY}",                         # 01/25/2024

      # European formats
      "{D}.{M}.{YYYY} {h24}:{m}",                # 25.12.2024 22:30
      "{D}.{M}.{YYYY}",                           # 25.12.2024
      "{0D}.{0M}.{YYYY}",                         # 01.12.2024
      "{D}-{M}-{YYYY}",                           # 25-12-2024

      # RFC formats
      "{RFC1123}",                                # Mon, 25 Dec 2024 10:30:00 GMT
      "{RFC3339}",                                # 2024-12-25T10:30:00+00:00
      "{RFC822}",                                 # Mon, 25 Dec 24 10:30:00 +0000

      # Natural month names
      "{Mfull} {D}, {YYYY} {h12}:{m} {AM}",      # December 25, 2024 10:30 AM
      "{Mfull} {D}, {YYYY}",                     # December 25, 2024
      "{D} {Mfull} {YYYY}",                      # 25 December 2024
      "{Mshort} {D}, {YYYY}",                    # Dec 25, 2024
      "{D} {Mshort} {YYYY}",                     # 25 Dec 2024

      # Time with seconds
      "{YYYY}-{0M}-{0D} {h24}:{m}:{s}",          # 2024-12-25 10:30:45
      "{M}/{D}/{YYYY} {h12}:{m}:{s} {AM}",       # 12/25/2024 10:30:45 AM

      # Compact formats
      "{YYYY}{0M}{0D}",                          # 20241225
      "{YYYY}{0M}{0D}T{h24}{m}{s}"               # 20241225T103045
    ]

    # Also try strftime formats as a fallback
    strftime_formats = [
      "%Y-%m-%dT%H:%M:%S%z",                     # 2024-12-25T10:30:00+0000
      "%Y-%m-%dT%H:%M:%SZ",                      # 2024-12-25T10:30:00Z
      "%Y-%m-%dT%H:%M:%S",                       # 2024-12-25T10:30:00
      "%Y-%m-%d %H:%M:%S",                       # 2024-12-25 10:30:00
      "%Y-%m-%d",                                # 2024-12-25
      "%m/%d/%Y %I:%M %p",                       # 12/25/2024 10:30 AM
      "%m/%d/%Y %H:%M",                          # 12/25/2024 22:30
      "%m/%d/%Y",                                # 12/25/2024
      "%d.%m.%Y %H:%M",                          # 25.12.2024 22:30
      "%d.%m.%Y",                                # 25.12.2024
      "%B %d, %Y %I:%M %p",                      # December 25, 2024 10:30 AM
      "%B %d, %Y",                               # December 25, 2024
      "%d %B %Y",                                # 25 December 2024
      "%b %d, %Y",                               # Dec 25, 2024
      "%d %b %Y",                                # 25 Dec 2024
      "%a %b %d %H:%M:%S %z %Y"                 # Mon Dec 25 10:30:00 +0000 2024 (Twitter format)
    ]

    # Try Unix timestamp if string is numeric
    case try_unix_timestamp(string) do
      {:ok, datetime} -> datetime
      _ ->
        # Try Timex default formats
        case try_formats(string, formats, :default) do
          nil ->
            # Try strftime formats
            case try_formats(string, strftime_formats, :strftime) do
              nil ->
                # Try natural language parsing as last resort
                case try_natural_language(string) do
                  nil ->
                    Logger.warning("Could not parse datetime: #{string}")
                    nil
                  datetime -> datetime
                end
              datetime -> datetime
            end
          datetime -> datetime
        end
    end
  end

  def parse_datetime(_), do: nil

  @doc """
  Parses a date string without time information.
  Returns a DateTime at midnight UTC.
  """
  def parse_date(nil), do: nil

  def parse_date(string) when is_binary(string) do
    case parse_datetime(string) do
      %DateTime{} = dt ->
        # Reset to midnight UTC
        %{dt | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
      nil ->
        nil
    end
  end

  @doc """
  Parses a time string and combines it with a date.
  """
  def parse_time_with_date(nil, _date), do: nil
  def parse_time_with_date(_time, nil), do: nil

  def parse_time_with_date(time_string, %DateTime{} = date) when is_binary(time_string) do
    time_formats = [
      "{h24}:{m}:{s}",
      "{h24}:{m}",
      "{h12}:{m} {AM}",
      "{h12}:{m}:{s} {AM}"
    ]

    # Parse just the time component
    result = Enum.find_value(time_formats, fn format ->
      # Create a dummy date string with the time
      dummy_date = "2000-01-01 #{time_string}"
      case Timex.parse(dummy_date, "{YYYY}-{0M}-{0D} #{format}") do
        {:ok, dt} ->
          # Apply the parsed time to the given date
          %{date | hour: dt.hour, minute: dt.minute, second: dt.second}
        _ -> nil
      end
    end)

    result || date
  end

  # Private helper functions

  defp try_formats(string, formats, parser_type) do
    Enum.find_value(formats, fn format ->
      try do
        case parser_type do
          :default ->
            case Timex.parse(string, format) do
              {:ok, datetime} -> to_utc(datetime)
              _ -> nil
            end
          :strftime ->
            case Timex.parse(string, format, :strftime) do
              {:ok, datetime} -> to_utc(datetime)
              _ -> nil
            end
        end
      rescue
        _ -> nil
      end
    end)
  end

  defp try_unix_timestamp(string) do
    case Integer.parse(String.trim(string)) do
      {timestamp, ""} ->
        # Determine if it's seconds or milliseconds
        # Timestamps after year 2001 in seconds are > 1_000_000_000
        # Timestamps in milliseconds are > 1_000_000_000_000
        unix_seconds =
          if abs(timestamp) >= 1_000_000_000_000 do
            div(timestamp, 1000)  # Convert milliseconds to seconds
          else
            timestamp
          end

        case DateTime.from_unix(unix_seconds) do
          {:ok, datetime} -> {:ok, datetime}
          _ -> {:error, :invalid_timestamp}
        end
      _ ->
        {:error, :not_numeric}
    end
  end

  defp try_natural_language(string) do
    downcased = String.downcase(string)

    cond do
      String.contains?(downcased, "today") ->
        parse_relative_date(string, 0)

      String.contains?(downcased, "tomorrow") ->
        parse_relative_date(string, 1)

      String.contains?(downcased, "yesterday") ->
        parse_relative_date(string, -1)

      String.contains?(downcased, "next ") ->
        parse_next_weekday(string)

      String.contains?(downcased, "last ") ->
        parse_last_weekday(string)

      true ->
        nil
    end
  end

  defp parse_relative_date(string, days_offset) do
    # Extract time if present
    time_pattern = ~r/(\d{1,2}):?(\d{2})?\s*(am|pm)?/i

    base_date = Timex.today()
                |> Timex.shift(days: days_offset)
                |> Timex.to_datetime("Etc/UTC")

    case Regex.run(time_pattern, String.downcase(string)) do
      [_, hour_str, minute_str, am_pm] ->
        hour = String.to_integer(hour_str)
        minute = if minute_str && minute_str != "", do: String.to_integer(minute_str), else: 0

        # Adjust for AM/PM
        hour = case am_pm do
          "pm" when hour < 12 -> hour + 12
          "am" when hour == 12 -> 0
          _ -> hour
        end

        %{base_date | hour: hour, minute: minute, second: 0}

      _ ->
        base_date
    end
  end

  defp parse_next_weekday(string) do
    weekday_pattern = ~r/next\s+(\w+)/i

    case Regex.run(weekday_pattern, String.downcase(string)) do
      [_, weekday_name] ->
        target_weekday = weekday_to_number(weekday_name)
        if target_weekday do
          today = Timex.today()
          current_weekday = Timex.weekday(today)

          # Calculate days until next occurrence
          days_ahead = rem(target_weekday - current_weekday + 7, 7)
          days_ahead = if days_ahead == 0, do: 7, else: days_ahead

          parse_relative_date(string, days_ahead)
        else
          nil
        end
      _ ->
        nil
    end
  end

  defp parse_last_weekday(string) do
    weekday_pattern = ~r/last\s+(\w+)/i

    case Regex.run(weekday_pattern, String.downcase(string)) do
      [_, weekday_name] ->
        target_weekday = weekday_to_number(weekday_name)
        if target_weekday do
          today = Timex.today()
          current_weekday = Timex.weekday(today)

          # Calculate days since last occurrence
          days_ago = rem(current_weekday - target_weekday + 7, 7)
          days_ago = if days_ago == 0, do: 7, else: days_ago

          parse_relative_date(string, -days_ago)
        else
          nil
        end
      _ ->
        nil
    end
  end

  defp weekday_to_number(weekday_name) do
    case weekday_name do
      "monday" -> 1
      "tuesday" -> 2
      "wednesday" -> 3
      "thursday" -> 4
      "friday" -> 5
      "saturday" -> 6
      "sunday" -> 7
      _ -> nil
    end
  end

  defp to_utc(%DateTime{} = datetime) do
    case Timex.Timezone.convert(datetime, "Etc/UTC") do
      {:error, _} -> datetime  # Already UTC or can't convert
      converted -> converted
    end
  end

  defp to_utc(%NaiveDateTime{} = naive) do
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp to_utc(other), do: other
end