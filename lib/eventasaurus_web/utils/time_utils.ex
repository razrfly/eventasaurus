defmodule EventasaurusWeb.Utils.TimeUtils do
  @moduledoc """
  Shared utilities for time formatting and manipulation.
  """

  require Logger

  @doc """
  Format time as 24-hour format string for storage (e.g., "10:00", "14:30")
  """
  def format_time_value(hour, minute) do
    "#{String.pad_leading(to_string(hour), 2, "0")}:#{String.pad_leading(to_string(minute), 2, "0")}"
  end

  @doc """
  Format time for display in 12-hour format with AM/PM (e.g., "10:00 AM", "2:30 PM")
  """
  def format_time_display(hour, minute) do
    {display_hour, period} =
      cond do
        hour == 0 -> {12, "AM"}
        hour < 12 -> {hour, "AM"}
        hour == 12 -> {12, "PM"}
        true -> {hour - 12, "PM"}
      end

    "#{display_hour}:#{String.pad_leading(to_string(minute), 2, "0")} #{period}"
  end

  @doc """
  Parse time string into hour and minute integers
  Returns {:ok, {hour, minute}} or {:error, :invalid_format}
  """
  def parse_time_string(time_str) do
    case String.split(time_str, ":") do
      [hour_str, minute_str | _] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str) do
          {:ok, {hour, minute}}
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  @doc """
  Parse time string for sorting purposes
  Returns total minutes since midnight, or 0 for invalid format with warning
  """
  def parse_time_for_sort(time_str) do
    case parse_time_string(time_str) do
      {:ok, {hour, minute}} ->
        hour * 60 + minute

      {:error, _} ->
        Logger.warning("Invalid time format for sorting: #{time_str}")
        0
    end
  end

  @doc """
  Format time string (HH:MM) to 12-hour format with AM/PM
  Returns formatted string like "2:30 PM" or original string if parsing fails
  """
  def format_time_12hour(time_str) when is_binary(time_str) do
    case parse_time_string(time_str) do
      {:ok, {hour, minute}} -> format_time_display(hour, minute)
      {:error, _} -> time_str
    end
  end

  def format_time_12hour(_), do: ""
end
