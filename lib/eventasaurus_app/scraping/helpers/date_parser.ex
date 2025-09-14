defmodule EventasaurusApp.Scraping.Helpers.DateParser do
  @moduledoc """
  Utilities for parsing various date and time formats from scraped data.
  """

  require Logger

  @doc """
  Parses a date/time string into a DateTime struct.
  Handles various common formats from event websites.
  """
  def parse_datetime(nil), do: nil

  def parse_datetime(%DateTime{} = dt), do: dt

  def parse_datetime(string) when is_binary(string) do
    # Try various parsing strategies
    with {:error, _} <- parse_iso8601(string),
         {:error, _} <- parse_american_format(string),
         {:error, _} <- parse_natural_language(string),
         {:error, _} <- parse_unix_timestamp(string) do
      Logger.warning("Could not parse datetime: #{string}")
      nil
    else
      {:ok, datetime} -> datetime
    end
  end

  def parse_datetime(_), do: nil

  @doc """
  Parses a date string without time information.
  Returns a DateTime at midnight UTC.
  """
  def parse_date(nil), do: nil

  def parse_date(string) when is_binary(string) do
    formats = [
      # ISO format
      ~r/^(\d{4})-(\d{2})-(\d{2})$/,
      # American format
      ~r/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/,
      # European format
      ~r/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/
    ]

    Enum.find_value(formats, fn format ->
      case Regex.run(format, string) do
        [_, y, m, d] when format == hd(formats) ->
          create_datetime(y, m, d, "00", "00", "00")

        [_, m, d, y] ->
          create_datetime(y, m, d, "00", "00", "00")

        _ ->
          nil
      end
    end)
  end

  @doc """
  Parses a time string and combines it with a date.
  """
  def parse_time_with_date(nil, _date), do: nil
  def parse_time_with_date(_time, nil), do: nil

  def parse_time_with_date(time_string, %DateTime{} = date) when is_binary(time_string) do
    case parse_time_components(time_string) do
      {hour, minute} ->
        %{date | hour: hour, minute: minute, second: 0}

      nil ->
        date
    end
  end

  defp parse_iso8601(string) do
    case DateTime.from_iso8601(string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      error -> error
    end
  end

  defp parse_american_format(string) do
    # Matches formats like "12/31/2024 8:00 PM" or "12/31/2024 20:00"
    regex = ~r/^(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$/i

    case Regex.run(regex, string) do
      [_, month, day, year, hour, minute, second, am_pm] ->
        hour = adjust_hour_for_ampm(hour, am_pm)
        create_datetime(year, month, day, hour, minute, second || "00")

      [_, month, day, year, hour, minute] ->
        create_datetime(year, month, day, hour, minute, "00")

      _ ->
        {:error, :no_match}
    end
  end

  defp parse_natural_language(string) do
    # Handle formats like "Tomorrow at 8pm", "Next Friday 7:30pm", etc.
    # This is a simplified version - expand as needed
    cond do
      String.contains?(string, "tomorrow") ->
        parse_relative_date(string, 1)

      String.contains?(string, "today") ->
        parse_relative_date(string, 0)

      String.contains?(string, "next") ->
        parse_next_weekday(string)

      true ->
        {:error, :no_match}
    end
  end

  defp parse_unix_timestamp(string) do
    case Integer.parse(string) do
      {timestamp, ""} when timestamp > 1_000_000_000 ->
        {:ok, DateTime.from_unix!(timestamp)}

      _ ->
        {:error, :no_match}
    end
  end

  defp parse_relative_date(string, days_offset) do
    time_regex = ~r/(\d{1,2})(?::(\d{2}))?\s*(am|pm)?/i

    case Regex.run(time_regex, string) do
      [_, hour, minute, am_pm] ->
        hour = adjust_hour_for_ampm(hour, am_pm)

        DateTime.utc_now()
        |> DateTime.add(days_offset * 24 * 3600, :second)
        |> Map.put(:hour, String.to_integer(hour))
        |> Map.put(:minute, String.to_integer(minute || "0"))
        |> Map.put(:second, 0)
        |> then(&{:ok, &1})

      _ ->
        {:error, :no_time}
    end
  end

  defp parse_next_weekday(string) do
    weekdays = %{
      "monday" => 1,
      "tuesday" => 2,
      "wednesday" => 3,
      "thursday" => 4,
      "friday" => 5,
      "saturday" => 6,
      "sunday" => 7
    }

    weekday_regex = ~r/next\s+(\w+)/i

    case Regex.run(weekday_regex, String.downcase(string)) do
      [_, weekday] when is_map_key(weekdays, weekday) ->
        target_day = weekdays[weekday]
        current_day = Date.utc_today() |> Date.day_of_week()

        days_until = rem(target_day - current_day + 7, 7)
        days_until = if days_until == 0, do: 7, else: days_until

        parse_relative_date(string, days_until)

      _ ->
        {:error, :no_weekday}
    end
  end

  defp parse_time_components(time_string) do
    regex = ~r/^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$/i

    case Regex.run(regex, time_string) do
      [_, hour, minute, _second, am_pm] ->
        hour = adjust_hour_for_ampm(hour, am_pm)
        {String.to_integer(hour), String.to_integer(minute)}

      [_, hour, minute] ->
        {String.to_integer(hour), String.to_integer(minute)}

      _ ->
        nil
    end
  end

  defp adjust_hour_for_ampm(hour, am_pm) when is_binary(hour) do
    hour_int = String.to_integer(hour)

    case String.upcase(am_pm || "") do
      "PM" when hour_int < 12 -> hour_int + 12
      "AM" when hour_int == 12 -> 0
      _ -> hour_int
    end
    |> Integer.to_string()
  end

  defp create_datetime(year, month, day, hour, minute, second) do
    with {year_int, ""} <- Integer.parse(to_string(year)),
         {month_int, ""} <- Integer.parse(to_string(month)),
         {day_int, ""} <- Integer.parse(to_string(day)),
         {hour_int, ""} <- Integer.parse(to_string(hour)),
         {minute_int, ""} <- Integer.parse(to_string(minute)),
         {second_int, ""} <- Integer.parse(to_string(second)),
         {:ok, naive} <- NaiveDateTime.new(year_int, month_int, day_int, hour_int, minute_int, second_int),
         {:ok, datetime} <- DateTime.from_naive(naive, "Etc/UTC") do
      {:ok, datetime}
    else
      _ -> {:error, :invalid_datetime}
    end
  end
end