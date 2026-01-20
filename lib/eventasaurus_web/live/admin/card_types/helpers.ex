defmodule EventasaurusWeb.Admin.CardTypes.Helpers do
  @moduledoc """
  Shared helper functions for social card type modules.

  Provides common utilities for:
  - Sample DateTime construction for previews
  - Form parameter parsing (integers, floats, dates)
  - Sample date generation for screening/occurrence data
  """

  @doc """
  Creates a sample DateTime for preview purposes.

  Generates a DateTime `days_ahead` days in the future at the specified
  hour and minute in UTC.

  ## Parameters
    - `days_ahead` - Number of days from now (default: 3)
    - `hour` - Hour in 24h format (default: 20 for 8 PM)
    - `minute` - Minute (default: 0)

  ## Examples

      iex> Helpers.sample_datetime()
      # Returns DateTime ~3 days from now at 20:00:00 UTC

      iex> Helpers.sample_datetime(7, 19, 30)
      # Returns DateTime ~7 days from now at 19:30:00 UTC
  """
  @spec sample_datetime(integer(), integer(), integer()) :: DateTime.t()
  def sample_datetime(days_ahead \\ 3, hour \\ 20, minute \\ 0) do
    target_date =
      Date.utc_today()
      |> Date.add(days_ahead)

    {:ok, time} = Time.new(hour, minute, 0)
    {:ok, datetime} = DateTime.new(target_date, time)
    datetime
  end

  @doc """
  Generates a list of sample screening dates for movie previews.

  Returns a list of consecutive dates starting from tomorrow.

  ## Parameters
    - `count` - Number of dates to generate (default: 3)
    - `start_offset` - Days from today for first date (default: 1)

  ## Examples

      iex> Helpers.sample_screening_dates()
      [~D[2025-01-21], ~D[2025-01-22], ~D[2025-01-23]]

      iex> Helpers.sample_screening_dates(5, 2)
      # Returns 5 dates starting 2 days from today
  """
  @spec sample_screening_dates(integer(), integer()) :: [Date.t()]
  def sample_screening_dates(count \\ 3, start_offset \\ 1) do
    today = Date.utc_today()

    Enum.map(0..(count - 1), fn offset ->
      Date.add(today, start_offset + offset)
    end)
  end

  @doc """
  Parses a string value as an integer with a fallback default.

  Safely handles nil, empty strings, and invalid values by
  returning the default.

  ## Examples

      iex> Helpers.parse_int("42", 0)
      42

      iex> Helpers.parse_int("invalid", 10)
      10

      iex> Helpers.parse_int(nil, 5)
      5
  """
  @spec parse_int(String.t() | nil | integer(), integer()) :: integer()
  def parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  def parse_int(value, _default) when is_integer(value), do: value
  def parse_int(_, default), do: default

  @doc """
  Parses a string value as a float with a fallback default.

  Safely handles nil, empty strings, and invalid values by
  returning the default.

  ## Examples

      iex> Helpers.parse_float("7.4", 0.0)
      7.4

      iex> Helpers.parse_float("invalid", 5.0)
      5.0
  """
  @spec parse_float(String.t() | nil | float(), float()) :: float()
  def parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> default
    end
  end

  def parse_float(value, _default) when is_float(value), do: value
  def parse_float(_, default), do: default

  @doc """
  Parses a year string into a Date (January 1st of that year).

  Used for movie release date editing where only the year matters.

  ## Examples

      iex> Helpers.parse_year("1990", ~D[2000-01-01])
      ~D[1990-01-01]

      iex> Helpers.parse_year("invalid", ~D[2000-01-01])
      ~D[2000-01-01]
  """
  @spec parse_year(String.t() | nil, Date.t()) :: Date.t()
  def parse_year(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {year, _} when year >= 1800 and year <= 2200 -> Date.new!(year, 1, 1)
      _ -> default
    end
  end

  def parse_year(_, default), do: default
end
