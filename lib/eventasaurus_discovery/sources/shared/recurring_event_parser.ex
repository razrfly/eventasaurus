defmodule EventasaurusDiscovery.Sources.Shared.RecurringEventParser do
  @moduledoc """
  Shared helper for parsing recurring event schedules across trivia sources.

  Used by: Inquizition, Quizmeisters, and other recurring trivia sources.

  Provides common functionality for:
  - Parsing day of week from text
  - Parsing time from various formats (12h/24h, with dots or colons)
  - Calculating next occurrence in any timezone
  - Building recurrence rules for weekly events

  ## Examples

      iex> parse_day_of_week("Wednesdays at 7pm")
      {:ok, :wednesday}

      iex> parse_time("7:30pm")
      {:ok, ~T[19:30:00]}

      iex> next_occurrence(:tuesday, ~T[18:30:00], "Europe/London")
      #DateTime<...>  # Next Tuesday at 6:30pm London time in UTC
  """

  require Logger

  # Day of week patterns - defined as function to avoid compile-time Regex injection
  defp day_patterns do
    %{
      monday: ~r/\b(mondays?|mon)\b/i,
      tuesday: ~r/\b(tuesdays?|tues?)\b/i,
      wednesday: ~r/\b(wednesdays?|wed)\b/i,
      thursday: ~r/\b(thursdays?|thurs?)\b/i,
      friday: ~r/\b(fridays?|fri)\b/i,
      saturday: ~r/\b(saturdays?|sat)\b/i,
      sunday: ~r/\b(sundays?|sun)\b/i
    }
  end

  @doc """
  Parse day of week from text.

  Handles various formats: "Wednesdays", "Wed", "Wednesday nights", etc.

  ## Examples

      iex> parse_day_of_week("Wednesdays at 7pm")
      {:ok, :wednesday}

      iex> parse_day_of_week("Thurs 8pm")
      {:ok, :thursday}

      iex> parse_day_of_week("Tuesday nights")
      {:ok, :tuesday}
  """
  def parse_day_of_week(text) when is_binary(text) do
    text_lower = String.downcase(text)

    case Enum.find(day_patterns(), fn {_day, pattern} ->
           String.match?(text_lower, pattern)
         end) do
      {day, _pattern} -> {:ok, day}
      nil -> {:error, "Could not parse day of week from: #{text}"}
    end
  end

  def parse_day_of_week(nil), do: {:error, "Text is nil"}

  @doc """
  Parse time from text.

  Supports multiple formats:
  - 12-hour with dots: "6.30pm", "7.45pm" (UK format)
  - 12-hour with colons: "7:30pm", "8:00 PM"
  - 24-hour format: "19:30", "20:00"
  - Standalone hours: "7", "8" (defaults to PM in trivia context)

  ## Examples

      iex> parse_time("7pm")
      {:ok, ~T[19:00:00]}

      iex> parse_time("7:30pm")
      {:ok, ~T[19:30:00]}

      iex> parse_time("6.30pm")  # UK format
      {:ok, ~T[18:30:00]}

      iex> parse_time("19:30")  # 24-hour
      {:ok, ~T[19:30:00]}

      iex> parse_time("7")  # Standalone hour defaults to PM
      {:ok, ~T[19:00:00]}
  """
  def parse_time(text) when is_binary(text) do
    cond do
      # Match "7pm", "7:30pm", "7.30pm", "7 pm" (with dots or colons)
      time_12h = Regex.run(~r/(\d{1,2})(?:[:\.](\d{2}))?\s*(am|pm)/i, text) ->
        parse_12h_time(time_12h)

      # Match "20:00", "19:30" (24-hour format)
      time_24h = Regex.run(~r/(\d{1,2}):(\d{2})/, text) ->
        parse_24h_time(time_24h)

      # Match standalone hour "7", "8" - default to PM in trivia context
      hour = Regex.run(~r/\b(\d{1,2})\b/, text) ->
        parse_12h_time([nil, List.first(hour), "0", "pm"])

      true ->
        {:error, "Could not parse time from: #{text}"}
    end
  end

  def parse_time(nil), do: {:error, "Text is nil"}

  @doc """
  Calculate the next occurrence of a specific day/time from now.

  Handles timezone conversion and returns a DateTime in UTC.

  ## Parameters
  - `day_of_week` - Day as atom (:monday, :tuesday, etc.)
  - `time` - Time struct
  - `timezone` - IANA timezone string (e.g., "Europe/London", "Australia/Sydney")

  ## Examples

      iex> next_occurrence(:tuesday, ~T[18:30:00], "Europe/London")
      ~U[2025-10-21 17:30:00Z]  # Next Tuesday at 6:30pm GMT

      iex> next_occurrence(:wednesday, ~T[19:00:00], "Australia/Sydney")
      ~U[2025-10-22 09:00:00Z]  # Next Wednesday at 7pm AEDT
  """
  def next_occurrence(day_of_week, time, timezone) do
    now = DateTime.now!(timezone)
    target_day_num = day_to_number(day_of_week)
    current_day_num = Date.day_of_week(DateTime.to_date(now), :monday)

    # Calculate days until target day
    days_ahead =
      cond do
        target_day_num > current_day_num ->
          target_day_num - current_day_num

        target_day_num < current_day_num ->
          7 - current_day_num + target_day_num

        true ->
          # Same day - check if time has passed
          current_time = DateTime.to_time(now)

          if Time.compare(time, current_time) == :gt do
            0
          else
            7
          end
      end

    # Create target date
    target_date = Date.add(DateTime.to_date(now), days_ahead)

    # Combine date and time in local timezone
    {:ok, naive_dt} = NaiveDateTime.new(target_date, time)
    {:ok, local_dt} = DateTime.from_naive(naive_dt, timezone)

    # Convert to UTC
    DateTime.shift_zone!(local_dt, "Etc/UTC")
  end

  @doc """
  Build a recurrence rule map for weekly events.

  Returns a map compatible with the recurrence_rule field in events.

  ## Examples

      iex> build_recurrence_rule(:tuesday, ~T[18:30:00], "Europe/London")
      %{
        "frequency" => "weekly",
        "days_of_week" => ["tuesday"],
        "time" => "18:30",
        "timezone" => "Europe/London"
      }
  """
  def build_recurrence_rule(day_atom, time, timezone) do
    %{
      "frequency" => "weekly",
      "days_of_week" => [Atom.to_string(day_atom)],
      "time" => Time.to_string(time) |> String.slice(0, 5),
      "timezone" => timezone
    }
  end

  # Private functions

  defp parse_12h_time([_full, hour, minutes, meridiem]) do
    hour_int = String.to_integer(hour)

    minutes_int =
      if minutes && minutes != "" do
        String.to_integer(minutes)
      else
        0
      end

    meridiem_lower = String.downcase(meridiem)

    # Convert to 24-hour format
    hour_24 =
      cond do
        meridiem_lower == "am" and hour_int == 12 -> 0
        meridiem_lower == "pm" and hour_int != 12 -> hour_int + 12
        true -> hour_int
      end

    case Time.new(hour_24, minutes_int, 0) do
      {:ok, time} -> {:ok, time}
      {:error, _} -> {:error, "Invalid time: #{hour}:#{minutes || 0} #{meridiem}"}
    end
  end

  defp parse_24h_time([_full, hour, minutes]) do
    hour_int = String.to_integer(hour)
    minutes_int = String.to_integer(minutes)

    case Time.new(hour_int, minutes_int, 0) do
      {:ok, time} -> {:ok, time}
      {:error, _} -> {:error, "Invalid time: #{hour}:#{minutes}"}
    end
  end

  # Convert day atom to ISO day number (1 = Monday, 7 = Sunday)
  defp day_to_number(:monday), do: 1
  defp day_to_number(:tuesday), do: 2
  defp day_to_number(:wednesday), do: 3
  defp day_to_number(:thursday), do: 4
  defp day_to_number(:friday), do: 5
  defp day_to_number(:saturday), do: 6
  defp day_to_number(:sunday), do: 7
end
