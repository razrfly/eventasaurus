defmodule EventasaurusDiscovery.Sources.WeekPl.Helpers.TimeConverter do
  @moduledoc """
  Convert week.pl slot times (minutes from midnight) to DateTime.

  ## Examples
      iex> TimeConverter.convert_minutes_to_time(1140, ~D[2025-11-20], "Europe/Warsaw")
      {:ok, ~U[2025-11-20 18:00:00Z]}  # 1140 minutes = 7:00 PM local → 6:00 PM UTC (winter)

      iex> TimeConverter.convert_minutes_to_time(600, ~D[2025-11-20], "Europe/Warsaw")
      {:ok, ~U[2025-11-20 09:00:00Z]}  # 600 minutes = 10:00 AM local → 9:00 AM UTC

  ## Slot Examples
  - 600 = 10:00 AM
  - 720 = 12:00 PM
  - 780 = 1:00 PM
  - 1140 = 7:00 PM
  - 1320 = 10:00 PM
  """

  @doc """
  Convert minutes from midnight to UTC DateTime.

  ## Parameters
  - minutes: Integer minutes from midnight (e.g., 1140 = 7:00 PM)
  - date: Date for the occurrence
  - timezone: IANA timezone string (e.g., "Europe/Warsaw")

  ## Returns
  {:ok, DateTime.t()} | {:error, :invalid_timezone}
  """
  def convert_minutes_to_time(minutes, date, timezone) do
    # Calculate hours and minutes
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    # Create naive datetime in local timezone
    {:ok, naive_dt} = NaiveDateTime.new(date, Time.new!(hours, mins, 0))

    # Convert to UTC using timezone
    case DateTime.from_naive(naive_dt, timezone) do
      {:ok, local_dt} ->
        utc_dt = DateTime.shift_zone!(local_dt, "Etc/UTC")
        {:ok, utc_dt}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Convert minutes to human-readable time string (24-hour format).

  ## Examples
      iex> TimeConverter.format_time(1140)
      "19:00"

      iex> TimeConverter.format_time(600)
      "10:00"
  """
  def format_time(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    hour_str = String.pad_leading(Integer.to_string(hours), 2, "0")
    min_str = String.pad_leading(Integer.to_string(mins), 2, "0")
    "#{hour_str}:#{min_str}"
  end

  @doc """
  Get timezone for a Polish city.

  All Polish cities use Europe/Warsaw timezone.
  """
  def get_timezone(_city_name), do: "Europe/Warsaw"
end
