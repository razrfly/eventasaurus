defmodule EventasaurusDiscovery.Sources.Sortiraparis.Helpers.DateParser do
  @moduledoc """
  Parses date strings from Sortiraparis into structured DateTime lists.

  ## Supported Date Formats

  1. **Multi-date list**: "February 25, 27, 28, 2026"
     → [~U[2026-02-25 00:00:00Z], ~U[2026-02-27 00:00:00Z], ~U[2026-02-28 00:00:00Z]]

  2. **Date range**: "October 15, 2025 to January 19, 2026"
     → [~U[2025-10-15 00:00:00Z], ~U[2026-01-19 00:00:00Z]]

  3. **Single date with day**: "Friday, October 31, 2025"
     → [~U[2025-10-31 00:00:00Z]]

  4. **Date with time**: "Saturday October 11 at 12 noon"
     → [~U[2025-10-11 12:00:00Z]] (assuming current year)

  5. **Ticket sale date**: "on Saturday October 11 at 12 noon"
     → Filtered out (not an event date)

  ## Timezone Handling

  - All dates converted to UTC (Paris is UTC+1/+2)
  - Default time: 00:00:00 (midnight) if not specified
  - When time is specified: converted from Paris timezone to UTC

  ## Multi-Date Expansion

  For multi-date events, returns separate DateTime for each occurrence.
  Transformer will create individual event instances with unique external_ids.
  """

  require Logger

  @months %{
    "january" => 1,
    "february" => 2,
    "march" => 3,
    "april" => 4,
    "may" => 5,
    "june" => 6,
    "july" => 7,
    "august" => 8,
    "september" => 9,
    "october" => 10,
    "november" => 11,
    "december" => 12
  }

  @month_pattern "january|february|march|april|may|june|july|august|september|october|november|december"
  @day_pattern "monday|tuesday|wednesday|thursday|friday|saturday|sunday"

  @doc """
  Parse date string into list of UTC DateTimes.

  ## Parameters

  - `date_string` - Raw date string from HTML
  - `options` - Optional parsing options
    - `:default_year` - Year to use if not specified (defaults to current year)
    - `:timezone` - Source timezone (defaults to "Europe/Paris")

  ## Returns

  - `{:ok, [DateTime.t()]}` - List of parsed dates
  - `{:error, reason}` - Parsing failed

  ## Examples

      iex> parse_dates("February 25, 27, 28, 2026")
      {:ok, [~U[2026-02-25 00:00:00Z], ~U[2026-02-27 00:00:00Z], ~U[2026-02-28 00:00:00Z]]}

      iex> parse_dates("October 15, 2025 to January 19, 2026")
      {:ok, [~U[2025-10-15 00:00:00Z], ~U[2026-01-19 00:00:00Z]]}

      iex> parse_dates("Friday, October 31, 2025")
      {:ok, [~U[2025-10-31 00:00:00Z]]}
  """
  def parse_dates(date_string, options \\ %{})

  def parse_dates(date_string, options) when is_binary(date_string) do
    Logger.debug("📅 Parsing date string: #{date_string}")

    cond do
      # Pattern 1: Date range "October 15, 2025 to January 19, 2026" (check first - most specific)
      dates = parse_date_range(date_string, options) ->
        {:ok, dates}

      # Pattern 2: Multi-date list "February 25, 27, 28, 2026"
      dates = parse_multi_date_list(date_string, options) ->
        {:ok, dates}

      # Pattern 3: Date with time "Saturday October 11 at 12 noon"
      dates = parse_date_with_time(date_string, options) ->
        {:ok, [dates]}

      # Pattern 4: Single date "Friday, October 31, 2025" (check last - least specific)
      dates = parse_single_date(date_string, options) ->
        {:ok, [dates]}

      true ->
        Logger.warning("⚠️ Failed to parse date string: #{date_string}")
        {:error, :unsupported_date_format}
    end
  end

  def parse_dates(_, _), do: {:error, :invalid_input}

  @doc """
  Parse multi-date list like "February 25, 27, 28, 2026".

  Returns list of DateTimes, one for each date in the series.
  """
  def parse_multi_date_list(date_string, options) do
    # Pattern: "February 25, 27, 28, 2026" or "October 11, 12, 13, 2025"
    # First check if this matches the pattern
    pattern = ~r/(#{@month_pattern})\s+(\d+(?:,\s*\d+)*),\s*(\d{4})/i

    case Regex.run(pattern, date_string) do
      [_, month_name, days_string, year_string] ->
        month = parse_month(month_name)
        year = String.to_integer(year_string)

        # Extract all day numbers from the comma-separated string
        days =
          days_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.to_integer/1)

        # Create DateTime for each day
        days
        |> Enum.map(fn day ->
          create_datetime(year, month, day, 0, 0, options)
        end)
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          dates -> dates
        end

      _ ->
        nil
    end
  end

  @doc """
  Parse date range like "October 15, 2025 to January 19, 2026".

  Returns list with start and end dates.
  """
  def parse_date_range(date_string, options) do
    # Pattern: "October 15, 2025 to January 19, 2026"
    pattern = ~r/(#{@month_pattern})\s+(\d+),\s*(\d{4})\s+to\s+(#{@month_pattern})\s+(\d+),\s*(\d{4})/i

    case Regex.run(pattern, date_string) do
      [_, start_month, start_day, start_year, end_month, end_day, end_year] ->
        start_dt =
          create_datetime(
            String.to_integer(start_year),
            parse_month(start_month),
            String.to_integer(start_day),
            0,
            0,
            options
          )

        end_dt =
          create_datetime(
            String.to_integer(end_year),
            parse_month(end_month),
            String.to_integer(end_day),
            0,
            0,
            options
          )

        if start_dt && end_dt do
          [start_dt, end_dt]
        else
          nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Parse single date like "Friday, October 31, 2025".

  Returns single DateTime.
  """
  def parse_single_date(date_string, options) do
    patterns = [
      # "Friday, October 31, 2025"
      ~r/(?:#{@day_pattern},\s*)?(#{@month_pattern})\s+(\d+),\s*(\d{4})/i,
      # "October 31, 2025" (without day name)
      ~r/(#{@month_pattern})\s+(\d+),\s*(\d{4})/i
    ]

    patterns
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, date_string) do
        [_, month_name, day, year] ->
          create_datetime(
            String.to_integer(year),
            parse_month(month_name),
            String.to_integer(day),
            0,
            0,
            options
          )

        _ ->
          nil
      end
    end)
  end

  @doc """
  Parse date with time like "Saturday October 11 at 12 noon".

  Returns DateTime with specified time.
  """
  def parse_date_with_time(date_string, options) do
    # Pattern: "Saturday October 11 at 12 noon" or "October 11 at 20:30"
    pattern = ~r/(?:#{@day_pattern}\s+)?(#{@month_pattern})\s+(\d+)(?:\s+at\s+(\d+)(?::(\d+))?(?:\s*(am|pm|noon))?)?/i

    case Regex.run(pattern, date_string) do
      [_, month_name, day | time_parts] ->
        month = parse_month(month_name)
        day_int = String.to_integer(day)

        # Default to current year if not specified
        year = Map.get(options, :default_year, DateTime.utc_now().year)

        # Parse time components
        {hour, minute} = parse_time_components(time_parts)

        create_datetime(year, month, day_int, hour, minute, options)

      _ ->
        nil
    end
  end

  # Private helper functions

  defp parse_month(month_name) when is_binary(month_name) do
    month_name
    |> String.downcase()
    |> String.trim()
    |> then(&Map.get(@months, &1))
  end

  defp parse_time_components([]), do: {0, 0}
  defp parse_time_components([""]), do: {0, 0}

  defp parse_time_components([hour_str | rest]) when is_binary(hour_str) and hour_str != "" do
    hour = String.to_integer(hour_str)

    minute =
      case rest do
        [minute_str | _] when is_binary(minute_str) and minute_str != "" ->
          String.to_integer(minute_str)

        _ ->
          0
      end

    # Check for am/pm/noon modifier
    modifier =
      rest
      |> List.last()
      |> then(fn m -> if is_binary(m), do: String.downcase(m), else: nil end)

    hour =
      case modifier do
        "pm" when hour < 12 -> hour + 12
        "am" when hour == 12 -> 0
        "noon" -> 12
        _ -> hour
      end

    {hour, minute}
  end

  defp parse_time_components(_), do: {0, 0}

  defp create_datetime(year, month, day, hour, minute, options) when is_integer(month) do
    timezone = Map.get(options, :timezone, "Europe/Paris")

    # Create naive datetime first
    case NaiveDateTime.new(year, month, day, hour, minute, 0) do
      {:ok, naive_dt} ->
        # Convert from Paris timezone to UTC
        case DateTime.from_naive(naive_dt, timezone) do
          {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
          {:ambiguous, dt1, _dt2} -> DateTime.shift_zone!(dt1, "Etc/UTC")
          {:gap, dt1, _dt2} -> DateTime.shift_zone!(dt1, "Etc/UTC")
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp create_datetime(_, _, _, _, _, _), do: nil
end
