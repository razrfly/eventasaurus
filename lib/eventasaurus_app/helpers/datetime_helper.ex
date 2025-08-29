defmodule EventasaurusApp.DateTimeHelper do
  @moduledoc """
  Centralized helper module for all datetime operations in Eventasaurus.
  
  This module ensures consistent handling of dates, times, and timezones throughout
  the application. All datetime values are stored in UTC and converted to/from
  user timezones for display and input.
  
  ## Core Principles
  - Always store datetimes in UTC in the database
  - Always convert user input from their selected timezone to UTC
  - Always convert UTC to user's timezone for display
  - Handle DST transitions gracefully
  - Provide clear fallback behavior for edge cases
  """
  
  
  @doc """
  Parses a date and time input from a form and converts it to UTC.
  
  ## Parameters
    - date_str: Date string in ISO8601 format (YYYY-MM-DD)
    - time_str: Time string in HH:MM format (24-hour)
    - timezone: IANA timezone string (e.g., "America/New_York")
    
  ## Returns
    - {:ok, DateTime.t()} with UTC timezone
    - {:error, reason} if parsing or conversion fails
    
  ## Examples
      iex> parse_user_datetime("2024-01-15", "14:30", "America/New_York")
      {:ok, ~U[2024-01-15 19:30:00Z]}
      
      iex> parse_user_datetime("2024-03-10", "02:30", "America/New_York")
      {:error, :nonexistent_time} # DST spring forward gap
  """
  def parse_user_datetime(date_str, time_str, timezone \\ "UTC")
  
  def parse_user_datetime(date_str, time_str, timezone) 
      when is_binary(date_str) and is_binary(time_str) and 
           date_str != "" and time_str != "" do
    with {:ok, date} <- Date.from_iso8601(date_str),
         {:ok, time} <- parse_time_string(time_str),
         {:ok, naive_datetime} <- NaiveDateTime.new(date, time),
         {:ok, utc_datetime} <- naive_to_utc(naive_datetime, timezone) do
      {:ok, utc_datetime}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_datetime}
    end
  end
  
  def parse_user_datetime(_, _, _), do: {:error, :missing_input}
  
  @doc """
  Parses a datetime-local input (from HTML form) and converts to UTC.
  
  ## Parameters
    - datetime_str: String from datetime-local input (e.g., "2024-01-15T14:30")
    - timezone: IANA timezone string
    
  ## Returns
    - {:ok, DateTime.t()} in UTC
    - {:error, reason} if parsing fails
  """
  def parse_datetime_local(datetime_str, timezone \\ "UTC")
  
  def parse_datetime_local(datetime_str, timezone) when is_binary(datetime_str) and datetime_str != "" do
    # Handle different formats
    cond do
      # Already has timezone info (Z or offset)
      String.contains?(datetime_str, "Z") or String.contains?(datetime_str, "+") ->
        case DateTime.from_iso8601(datetime_str) do
          {:ok, datetime, _} -> {:ok, datetime}
          {:error, _} -> {:error, :invalid_format}
        end
      
      # Local datetime format (YYYY-MM-DDTHH:MM or YYYY-MM-DDTHH:MM:SS)
      String.contains?(datetime_str, "T") ->
        # Ensure we have seconds in the string
        normalized_str = case String.split(datetime_str, ":") do
          [_date_hour, _min] -> datetime_str <> ":00"  # Add seconds if missing
          [_date_hour, _min, _sec] -> datetime_str      # Already has seconds
          _ -> datetime_str  # Let it fail in parsing
        end
        
        # Parse as naive and convert using timezone
        with {:ok, naive} <- NaiveDateTime.from_iso8601(normalized_str),
             {:ok, utc_datetime} <- naive_to_utc(naive, timezone) do
          {:ok, utc_datetime}
        else
          _ -> {:error, :conversion_failed}
        end
      
      true ->
        {:error, :invalid_format}
    end
  end
  
  def parse_datetime_local(_, _), do: {:error, :missing_input}
  
  @doc """
  Converts a UTC datetime to a user's timezone for display.
  
  ## Parameters
    - datetime: DateTime in UTC
    - timezone: Target IANA timezone string
    
  ## Returns
    - DateTime in the specified timezone
    - Original datetime if conversion fails
  """
  def utc_to_timezone(nil, _timezone), do: nil
  
  def utc_to_timezone(%DateTime{} = datetime, timezone) when is_binary(timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, shifted} -> shifted
      {:error, _} -> datetime  # Fallback to original
    end
  end
  
  def utc_to_timezone(datetime, _), do: datetime
  
  @doc """
  Formats a UTC datetime for display in a specific timezone.
  Returns separate date and time strings for form inputs.
  
  ## Returns
    - {date_string, time_string} tuple
    - {nil, nil} if datetime is nil
    
  ## Examples
      iex> format_for_form(~U[2024-01-15 19:30:00Z], "America/New_York")
      {"2024-01-15", "14:30"}
  """
  def format_for_form(nil, _timezone), do: {nil, nil}
  
  def format_for_form(%DateTime{} = datetime, timezone) do
    shifted = utc_to_timezone(datetime, timezone)
    
    date_str = shifted |> DateTime.to_date() |> Date.to_iso8601()
    time_str = shifted |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
    
    {date_str, time_str}
  end
  
  @doc """
  Formats a datetime for user display with timezone information.
  
  ## Examples
      iex> format_for_display(~U[2024-01-15 19:30:00Z], "America/New_York")
      "Jan 15, 2024 at 2:30 PM EST"
  """
  def format_for_display(nil, _timezone), do: ""
  
  def format_for_display(%DateTime{} = datetime, timezone) do
    shifted = utc_to_timezone(datetime, timezone)
    
    # Format: "Jan 15, 2024 at 2:30 PM EST"
    month = format_month(shifted.month)
    day = shifted.day
    year = shifted.year
    {hour_12, period} = to_12_hour(shifted.hour)
    minute = String.pad_leading("#{shifted.minute}", 2, "0")
    tz_abbr = get_timezone_abbreviation(timezone, shifted)
    
    "#{month} #{day}, #{year} at #{hour_12}:#{minute} #{period} #{tz_abbr}"
  end
  
  @doc """
  Validates that a datetime is not in the past.
  
  ## Returns
    - :ok if datetime is in the future
    - {:error, :past_datetime} if in the past
  """
  def validate_future_datetime(%DateTime{} = datetime) do
    if DateTime.compare(datetime, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, :past_datetime}
    end
  end
  
  def validate_future_datetime(_), do: {:error, :invalid_datetime}
  
  @doc """
  Checks if a time falls within DST transition gaps or overlaps.
  
  ## Returns
    - {:ok, datetime} if time is valid
    - {:gap, before, after} if time falls in DST spring-forward gap
    - {:ambiguous, first, second} if time occurs twice due to fall-back
  """
  def check_dst_transition(naive_datetime, timezone) do
    case DateTime.from_naive(naive_datetime, timezone) do
      {:ok, datetime} -> 
        {:ok, datetime}
      {:gap, gap_before, gap_after} -> 
        # Time doesn't exist due to DST spring forward
        {:gap, gap_before, gap_after}
      {:ambiguous, first, second} -> 
        # Time occurs twice due to DST fall back
        {:ambiguous, first, second}
      error -> 
        error
    end
  end
  
  # Private helper functions
  
  defp naive_to_utc(naive_datetime, timezone) do
    case DateTime.from_naive(naive_datetime, timezone) do
      {:ok, datetime} ->
        DateTime.shift_zone(datetime, "UTC")
      
      {:gap, _before, _after} ->
        # Return specific error for nonexistent time during DST spring forward
        {:error, :nonexistent_datetime}
      
      {:ambiguous, _first, _second} ->
        # Return specific error for ambiguous time during DST fall back
        {:error, :ambiguous_datetime}
      
      error ->
        error
    end
  end
  
  defp parse_time_string(time_str) do
    # Handle both HH:MM and HH:MM:SS formats
    time_with_seconds = 
      case String.split(time_str, ":") do
        [_h, _m] -> time_str <> ":00"
        [_h, _m, _s] -> time_str
        _ -> nil
      end
    
    if time_with_seconds do
      Time.from_iso8601(time_with_seconds)
    else
      {:error, :invalid_time_format}
    end
  end
  
  defp to_12_hour(hour) do
    cond do
      hour == 0 -> {12, "AM"}
      hour < 12 -> {hour, "AM"}
      hour == 12 -> {12, "PM"}
      true -> {hour - 12, "PM"}
    end
  end
  
  defp format_month(1), do: "Jan"
  defp format_month(2), do: "Feb"
  defp format_month(3), do: "Mar"
  defp format_month(4), do: "Apr"
  defp format_month(5), do: "May"
  defp format_month(6), do: "Jun"
  defp format_month(7), do: "Jul"
  defp format_month(8), do: "Aug"
  defp format_month(9), do: "Sep"
  defp format_month(10), do: "Oct"
  defp format_month(11), do: "Nov"
  defp format_month(12), do: "Dec"
  
  defp get_timezone_abbreviation(_timezone, %DateTime{} = datetime) do
    # Prefer the system-provided abbreviation; fallback to numeric UTC offset
    case datetime.zone_abbr do
      abbr when is_binary(abbr) and byte_size(abbr) in 2..5 ->
        abbr
      _ ->
        offset_seconds = datetime.utc_offset + datetime.std_offset
        format_utc_offset(offset_seconds)
    end
  end
  
  defp format_utc_offset(seconds) do
    total = abs(seconds)
    sign = if seconds >= 0, do: "+", else: "-"
    hours = div(total, 3600)
    minutes = div(rem(total, 3600), 60)
    "UTC#{sign}#{String.pad_leading("#{hours}", 2, "0")}:#{String.pad_leading("#{minutes}", 2, "0")}"
  end
  
  @doc """
  Combines separate date and time inputs into a single UTC datetime.
  This is the main function that should be used for all form submissions.
  
  ## Parameters
    - params: Map containing "date" and "time" keys
    - timezone: User's timezone for conversion
    - date_key: Key for date in params (default: "date")
    - time_key: Key for time in params (default: "time")
    
  ## Returns
    - {:ok, DateTime.t()} in UTC
    - {:error, reason} if parsing fails
  """
  def combine_date_time_params(params, timezone, date_key \\ "date", time_key \\ "time") do
    date_str = Map.get(params, date_key, "")
    time_str = Map.get(params, time_key, "")
    
    parse_user_datetime(date_str, time_str, timezone)
  end
end