defmodule EventasaurusWeb.Utils.TimeUtils do
  @moduledoc """
  Centralized time formatting and manipulation utilities for Eventasaurus.

  This module provides a single source of truth for all time-related formatting,
  ensuring consistent display across the application.

  ## Time Format Styles

  - `:format_24h` - 24-hour format (e.g., "14:30", "09:00") - European standard
  - `:format_12h` - 12-hour format with AM/PM (e.g., "2:30 PM", "9:00 AM") - US standard

  ## Usage

      # Format a Time struct
      TimeUtils.format_time(~T[14:30:00], :format_24h)  # => "14:30"
      TimeUtils.format_time(~T[14:30:00], :format_12h)  # => "2:30 PM"

      # Format a time string
      TimeUtils.format_time("14:30", :format_24h)  # => "14:30"
      TimeUtils.format_time("14:30", :format_12h)  # => "2:30 PM"

      # Format a DateTime
      TimeUtils.format_datetime(datetime, timezone, :short)
      TimeUtils.format_datetime(datetime, timezone, :full)
  """

  require Logger

  # Default format for user-facing time display
  # Using 24-hour format as the application primarily serves European users
  @default_time_format :format_24h

  @doc """
  Returns the default time format style for the application.

  Currently returns `:format_24h` for European users.
  """
  @spec default_time_format() :: :format_24h | :format_12h
  def default_time_format, do: @default_time_format

  # ============================================================================
  # TIME FORMATTING
  # ============================================================================

  @doc """
  Formats a time value with the specified style.

  ## Parameters

  - `time` - A Time struct, DateTime struct, or time string ("HH:MM" or "HH:MM:SS")
  - `style` - `:format_24h` or `:format_12h` (optional, defaults to application default)

  ## Returns

  Formatted time string, or empty string on invalid input

  ## Examples

      iex> format_time(~T[14:30:00], :format_24h)
      "14:30"

      iex> format_time(~T[14:30:00], :format_12h)
      "2:30 PM"

      iex> format_time("14:30", :format_12h)
      "2:30 PM"

      iex> format_time(~U[2024-01-15 14:30:00Z], :format_24h)
      "14:30"
  """
  @spec format_time(Time.t() | DateTime.t() | String.t() | nil, :format_24h | :format_12h) ::
          String.t()
  def format_time(time, style \\ @default_time_format)

  def format_time(nil, _style), do: ""

  def format_time(%Time{hour: hour, minute: minute}, style) do
    format_hour_minute(hour, minute, style)
  end

  def format_time(%DateTime{hour: hour, minute: minute}, style) do
    format_hour_minute(hour, minute, style)
  end

  def format_time(time_str, style) when is_binary(time_str) do
    case parse_time_string(time_str) do
      {:ok, {hour, minute}} -> format_hour_minute(hour, minute, style)
      {:error, _} -> time_str
    end
  end

  def format_time(_, _), do: ""

  @doc """
  Formats hour and minute integers with the specified style.

  ## Parameters

  - `hour` - Hour (0-23)
  - `minute` - Minute (0-59)
  - `style` - `:format_24h` or `:format_12h`

  ## Examples

      iex> format_hour_minute(14, 30, :format_24h)
      "14:30"

      iex> format_hour_minute(14, 30, :format_12h)
      "2:30 PM"
  """
  @spec format_hour_minute(integer(), integer(), :format_24h | :format_12h) :: String.t()
  def format_hour_minute(hour, minute, :format_24h) do
    "#{pad_number(hour)}:#{pad_number(minute)}"
  end

  def format_hour_minute(hour, minute, :format_12h) do
    {display_hour, period} = to_12_hour(hour)
    "#{display_hour}:#{pad_number(minute)} #{period}"
  end

  # ============================================================================
  # DATETIME FORMATTING
  # ============================================================================

  @doc """
  Formats a datetime for display with timezone awareness.

  ## Parameters

  - `datetime` - A DateTime struct
  - `timezone` - Target IANA timezone string for display
  - `style` - Format style (see below)

  ## Styles

  - `:full` - "Monday, January 15, 2024 at 14:30" (or "2:30 PM" for 12h)
  - `:short` - "Jan 15 at 14:30"
  - `:date_only` - "January 15, 2024"
  - `:time_only` - "14:30" or "2:30 PM"
  - `:compact` - "Jan 15, 14:30"

  ## Options

  - `:time_format` - Override time format (`:format_24h` or `:format_12h`)

  ## Examples

      iex> format_datetime(~U[2024-01-15 13:30:00Z], "Europe/Warsaw", :full)
      "Monday, January 15, 2024 at 14:30"

      iex> format_datetime(~U[2024-01-15 13:30:00Z], "Europe/Warsaw", :time_only)
      "14:30"
  """
  @spec format_datetime(DateTime.t() | nil, String.t(), atom(), keyword()) :: String.t()
  def format_datetime(datetime, timezone, style, opts \\ [])

  def format_datetime(nil, _timezone, _style, _opts), do: ""

  def format_datetime(%DateTime{} = datetime, timezone, style, opts) do
    time_format = Keyword.get(opts, :time_format, @default_time_format)

    shifted =
      case DateTime.shift_zone(datetime, timezone) do
        {:ok, dt} -> dt
        {:error, _} -> datetime
      end

    format_shifted_datetime(shifted, style, time_format)
  end

  defp format_shifted_datetime(dt, :full, time_format) do
    day_name = Calendar.strftime(dt, "%A")
    month_name = Calendar.strftime(dt, "%B")
    time_str = format_time(dt, time_format)

    "#{day_name}, #{month_name} #{dt.day}, #{dt.year} at #{time_str}"
  end

  defp format_shifted_datetime(dt, :short, time_format) do
    month_abbr = Calendar.strftime(dt, "%b")
    time_str = format_time(dt, time_format)

    "#{month_abbr} #{dt.day} at #{time_str}"
  end

  defp format_shifted_datetime(dt, :date_only, _time_format) do
    month_name = Calendar.strftime(dt, "%B")
    "#{month_name} #{dt.day}, #{dt.year}"
  end

  defp format_shifted_datetime(dt, :time_only, time_format) do
    format_time(dt, time_format)
  end

  defp format_shifted_datetime(dt, :compact, time_format) do
    month_abbr = Calendar.strftime(dt, "%b")
    time_str = format_time(dt, time_format)

    "#{month_abbr} #{dt.day}, #{time_str}"
  end

  defp format_shifted_datetime(dt, _unknown_style, time_format) do
    # Default to :full for unknown styles
    format_shifted_datetime(dt, :full, time_format)
  end

  # ============================================================================
  # TIME PARSING
  # ============================================================================

  @doc """
  Parses a time string into hour and minute integers.

  Handles both "HH:MM" and "HH:MM:SS" formats.

  ## Returns

  - `{:ok, {hour, minute}}` on success
  - `{:error, :invalid_format}` on failure

  ## Examples

      iex> parse_time_string("14:30")
      {:ok, {14, 30}}

      iex> parse_time_string("14:30:00")
      {:ok, {14, 30}}

      iex> parse_time_string("invalid")
      {:error, :invalid_format}
  """
  @spec parse_time_string(String.t()) :: {:ok, {integer(), integer()}} | {:error, :invalid_format}
  def parse_time_string(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [hour_str, minute_str | _] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str),
             true <- hour >= 0 and hour <= 23,
             true <- minute >= 0 and minute <= 59 do
          {:ok, {hour, minute}}
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  def parse_time_string(_), do: {:error, :invalid_format}

  @doc """
  Parses a time string into a Time struct.

  ## Returns

  - `{:ok, Time.t()}` on success
  - `{:error, :invalid_format}` on failure
  """
  @spec parse_time_to_struct(String.t()) :: {:ok, Time.t()} | {:error, :invalid_format}
  def parse_time_to_struct(time_str) when is_binary(time_str) do
    case parse_time_string(time_str) do
      {:ok, {hour, minute}} ->
        {:ok, Time.new!(hour, minute, 0)}

      error ->
        error
    end
  end

  def parse_time_to_struct(_), do: {:error, :invalid_format}

  @doc """
  Parses a time string for sorting purposes.

  Returns total minutes since midnight, or 0 for invalid format with warning.

  ## Examples

      iex> parse_time_for_sort("14:30")
      870

      iex> parse_time_for_sort("00:00")
      0
  """
  @spec parse_time_for_sort(String.t()) :: integer()
  def parse_time_for_sort(time_str) do
    case parse_time_string(time_str) do
      {:ok, {hour, minute}} ->
        hour * 60 + minute

      {:error, _} ->
        Logger.warning("Invalid time format for sorting: #{inspect(time_str)}")
        0
    end
  end

  # ============================================================================
  # LEGACY COMPATIBILITY FUNCTIONS
  # ============================================================================
  # These functions maintain backward compatibility with existing code.
  # New code should use format_time/2 with explicit style parameter.

  @doc """
  Format time as 24-hour format string for storage (e.g., "10:00", "14:30")

  This is a convenience function for database storage format.
  """
  @spec format_time_value(integer(), integer()) :: String.t()
  def format_time_value(hour, minute) do
    format_hour_minute(hour, minute, :format_24h)
  end

  @doc """
  Format time for display in 24-hour format (e.g., "10:00", "14:30")

  Legacy function - now uses 24-hour format by default.
  """
  @spec format_time_display(integer(), integer()) :: String.t()
  def format_time_display(hour, minute) do
    format_hour_minute(hour, minute, :format_24h)
  end

  @doc """
  Format time string (HH:MM) to 24-hour format.

  Legacy function - now uses 24-hour format by default.

  ## Examples

      iex> format_time_12hour("14:30")
      "14:30"

      iex> format_time_12hour("09:00")
      "09:00"
  """
  @spec format_time_12hour(String.t() | nil) :: String.t()
  def format_time_12hour(time_str) when is_binary(time_str) do
    format_time(time_str, :format_24h)
  end

  def format_time_12hour(_), do: ""

  @doc """
  Format time string (HH:MM) to 24-hour format.

  ## Examples

      iex> format_time_24hour("14:30")
      "14:30"

      iex> format_time_24hour("9:00")
      "09:00"
  """
  @spec format_time_24hour(String.t() | nil) :: String.t()
  def format_time_24hour(time_str) when is_binary(time_str) do
    format_time(time_str, :format_24h)
  end

  def format_time_24hour(_), do: ""

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp to_12_hour(hour) do
    cond do
      hour == 0 -> {12, "AM"}
      hour < 12 -> {hour, "AM"}
      hour == 12 -> {12, "PM"}
      true -> {hour - 12, "PM"}
    end
  end

  defp pad_number(num) when num < 10, do: "0#{num}"
  defp pad_number(num), do: "#{num}"
end
