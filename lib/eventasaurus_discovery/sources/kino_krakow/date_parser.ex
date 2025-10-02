defmodule EventasaurusDiscovery.Sources.KinoKrakow.DateParser do
  @moduledoc """
  Parses Polish date strings from Kino Krakow website.

  Examples:
    - "środa, 1 października" → 2024-10-01
    - "sobota, 5 października 2024" → 2024-10-05
    - "15:30" → combines with current date
  """

  @polish_months %{
    "stycznia" => 1,
    "lutego" => 2,
    "marca" => 3,
    "kwietnia" => 4,
    "maja" => 5,
    "czerwca" => 6,
    "lipca" => 7,
    "sierpnia" => 8,
    "września" => 9,
    "października" => 10,
    "listopada" => 11,
    "grudnia" => 12
  }

  @polish_days %{
    "poniedziałek" => 1,
    "wtorek" => 2,
    "środa" => 3,
    "czwartek" => 4,
    "piątek" => 5,
    "sobota" => 6,
    "niedziela" => 7
  }

  @doc """
  Parse Polish date string to Date struct.

  ## Examples

      iex> parse_date("środa, 1 października")
      ~D[2024-10-01]

      iex> parse_date("5 października 2024")
      ~D[2024-10-05]
  """
  def parse_date(date_string) when is_binary(date_string) do
    date_string
    |> String.downcase()
    |> String.trim()
    |> extract_date_parts()
    |> build_date()
  end

  @doc """
  Parse Polish time string to Time struct.

  ## Examples

      iex> parse_time("15:30")
      ~T[15:30:00]

      iex> parse_time("9:15")
      ~T[09:15:00]
  """
  def parse_time(time_string) when is_binary(time_string) do
    case String.split(time_string, ":") do
      [hour, minute] ->
        {:ok, time} =
          Time.new(
            String.to_integer(String.trim(hour)),
            String.to_integer(String.trim(minute)),
            0
          )

        time

      _ ->
        nil
    end
  end

  @doc """
  Combine date and time strings into DateTime.

  ## Examples

      iex> parse_datetime("środa, 1 października", "15:30")
      ~U[2024-10-01 15:30:00Z]
  """
  def parse_datetime(date_string, time_string) do
    date = parse_date(date_string)
    time = parse_time(time_string)

    case {date, time} do
      {%Date{} = d, %Time{} = t} ->
        {:ok, datetime} = DateTime.new(d, t, "Europe/Warsaw")
        DateTime.shift_zone!(datetime, "Etc/UTC")

      _ ->
        nil
    end
  end

  # Private functions

  defp extract_date_parts(date_string) do
    # Remove day name if present (środa, wtorek, etc.)
    date_string =
      Enum.reduce(@polish_days, date_string, fn {day, _}, acc ->
        String.replace(acc, day, "")
      end)

    # Extract day, month, year
    parts =
      date_string
      |> String.replace(",", "")
      |> String.split()
      |> Enum.reject(&(&1 == ""))

    %{
      day: find_day(parts),
      month: find_month(parts),
      year: find_year(parts)
    }
  end

  defp find_day(parts) do
    parts
    |> Enum.find_value(fn part ->
      case Integer.parse(part) do
        {day, ""} when day >= 1 and day <= 31 -> day
        _ -> nil
      end
    end)
  end

  defp find_month(parts) do
    parts
    |> Enum.find_value(fn part ->
      Map.get(@polish_months, part)
    end)
  end

  defp find_year(parts) do
    parts
    |> Enum.find_value(fn part ->
      case Integer.parse(part) do
        {year, ""} when year >= 2020 and year <= 2030 -> year
        _ -> nil
      end
    end) || Date.utc_today().year
  end

  defp build_date(%{day: day, month: month, year: year})
       when is_integer(day) and is_integer(month) and is_integer(year) do
    Date.new!(year, month, day)
  end

  defp build_date(_), do: nil
end
