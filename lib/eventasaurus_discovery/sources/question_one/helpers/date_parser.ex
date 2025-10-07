defmodule EventasaurusDiscovery.Sources.QuestionOne.Helpers.DateParser do
  @moduledoc """
  Parses Question One time text into structured day/time data.

  Question One provides schedule information in natural language formats:
  - "Wednesdays at 8pm"
  - "Every Monday at 7:30pm"
  - "Thursdays 8:00 PM"
  - "Tuesday nights at 7pm"

  This module extracts:
  - Day of week (as atom: :monday, :tuesday, etc.)
  - Start time (as Time struct)
  """

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
  Parse time text into day of week and start time.

  ## Examples
      iex> parse_time_text("Wednesdays at 8pm")
      {:ok, {:wednesday, ~T[20:00:00]}}

      iex> parse_time_text("Every Monday at 7:30pm")
      {:ok, {:monday, ~T[19:30:00]}}

      iex> parse_time_text("Thursdays 8:00 PM")
      {:ok, {:thursday, ~T[20:00:00]}}

  ## Returns
  - `{:ok, {day_atom, time_struct}}` - Successfully parsed
  - `{:error, reason}` - Parsing failed
  """
  def parse_time_text(text) when is_binary(text) do
    with {:ok, day} <- parse_day_of_week(text),
         {:ok, time} <- parse_time(text) do
      {:ok, {day, time}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_time_text(nil), do: {:error, "Time text is nil"}

  @doc """
  Extract day of week from text.

  ## Examples
      iex> parse_day_of_week("Wednesdays at 8pm")
      {:ok, :wednesday}

      iex> parse_day_of_week("Mon 7pm")
      {:ok, :monday}
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

  @doc """
  Extract time from text.

  Supports formats:
  - "8pm", "8:30pm"
  - "20:00", "19:30"
  - "8 PM", "7:30 PM"

  ## Examples
      iex> parse_time("at 8pm")
      {:ok, ~T[20:00:00]}

      iex> parse_time("7:30 PM")
      {:ok, ~T[19:30:00]}

      iex> parse_time("20:00")
      {:ok, ~T[20:00:00]}
  """
  def parse_time(text) when is_binary(text) do
    cond do
      # Match "8pm", "8:30pm", "8 pm", "8:30 pm"
      time_12h = Regex.run(~r/(\d{1,2})(?::(\d{2}))?\s*(am|pm)/i, text) ->
        parse_12h_time(time_12h)

      # Match "20:00", "19:30" (24-hour format)
      time_24h = Regex.run(~r/(\d{1,2}):(\d{2})/, text) ->
        parse_24h_time(time_24h)

      # Match standalone hour "8", "20"
      hour = Regex.run(~r/\b(\d{1,2})\b/, text) ->
        # Default to PM for single digit hours in trivia context
        parse_12h_time([nil, List.first(hour), "0", "pm"])

      true ->
        {:error, "Could not parse time from: #{text}"}
    end
  end

  # Parse 12-hour time format
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

  # Parse 24-hour time format
  defp parse_24h_time([_full, hour, minutes]) do
    hour_int = String.to_integer(hour)
    minutes_int = String.to_integer(minutes)

    case Time.new(hour_int, minutes_int, 0) do
      {:ok, time} -> {:ok, time}
      {:error, _} -> {:error, "Invalid time: #{hour}:#{minutes}"}
    end
  end

  @doc """
  Calculate the next occurrence of a specific day/time from now.

  Returns a DateTime in UTC.

  ## Examples
      iex> next_occurrence(:wednesday, ~T[20:00:00])
      ~U[2025-10-15 19:00:00Z]  # Next Wednesday at 8pm London time
  """
  def next_occurrence(day_of_week, time, timezone \\ "Europe/London") do
    now = DateTime.now!(timezone)
    target_day_num = day_to_number(day_of_week)
    current_day_num = Date.day_of_week(now, :monday)

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

  # Convert day atom to ISO day number (1 = Monday, 7 = Sunday)
  defp day_to_number(:monday), do: 1
  defp day_to_number(:tuesday), do: 2
  defp day_to_number(:wednesday), do: 3
  defp day_to_number(:thursday), do: 4
  defp day_to_number(:friday), do: 5
  defp day_to_number(:saturday), do: 6
  defp day_to_number(:sunday), do: 7
end
