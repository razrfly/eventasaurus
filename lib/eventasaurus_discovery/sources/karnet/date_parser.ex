defmodule EventasaurusDiscovery.Sources.Karnet.DateParser do
  @moduledoc """
  Parses Polish date formats from Karnet Kraków event pages.

  Handles various date formats including:
  - Single dates: "04.09.2025, 18:00"
  - Date ranges: "04.09.2025 - 09.10.2025"
  - Polish day names: "czwartek, 4 września 2025"
  - Time ranges: "18:00 - 20:00"
  """

  require Logger

  # Polish month names mapping
  @polish_months %{
    "stycznia" => 1,      "styczeń" => 1,
    "lutego" => 2,        "luty" => 2,
    "marca" => 3,         "marzec" => 3,
    "kwietnia" => 4,      "kwiecień" => 4,
    "maja" => 5,          "maj" => 5,
    "czerwca" => 6,       "czerwiec" => 6,
    "lipca" => 7,         "lipiec" => 7,
    "sierpnia" => 8,      "sierpień" => 8,
    "września" => 9,      "wrzesień" => 9,
    "października" => 10, "październik" => 10,
    "listopada" => 11,    "listopad" => 11,
    "grudnia" => 12,      "grudzień" => 12
  }

  # Polish day names (for reference)
  # Currently not used but kept for potential future use
  # @polish_days %{
  #   "poniedziałek" => 1,
  #   "wtorek" => 2,
  #   "środa" => 3,
  #   "czwartek" => 4,
  #   "piątek" => 5,
  #   "sobota" => 6,
  #   "niedziela" => 7
  # }

  @doc """
  Parse a date string and return start and end DateTimes.

  Returns {:ok, {start_datetime, end_datetime}} or {:error, reason}
  """
  def parse_date_string(nil), do: {:error, :no_date}
  def parse_date_string(""), do: {:error, :no_date}

  def parse_date_string(date_string) when is_binary(date_string) do
    cleaned = clean_date_string(date_string)

    cond do
      # Date range with hyphen: "04.09.2025 - 09.10.2025"
      String.contains?(cleaned, " - ") ->
        parse_date_range(cleaned)

      # Date range with comma separator: "04.09.2025, 18:00 - 09.10.2025"
      String.contains?(cleaned, ", ") && String.contains?(cleaned, "-") ->
        parse_date_range_with_time(cleaned)

      # Polish format with day name: "czwartek, 4 września 2025"
      Regex.match?(~r/\d+\s+(#{Enum.join(Map.keys(@polish_months), "|")})/i, cleaned) ->
        parse_polish_date(cleaned)

      # Standard format: "04.09.2025"
      Regex.match?(~r/\d{1,2}\.\d{1,2}\.\d{4}/, cleaned) ->
        parse_standard_date(cleaned)

      # ISO format: "2025-09-04"
      Regex.match?(~r/\d{4}-\d{2}-\d{2}/, cleaned) ->
        parse_iso_date(cleaned)

      true ->
        Logger.warning("Unknown date format: #{date_string}")
        {:error, :unknown_format}
    end
  end

  defp clean_date_string(date_string) do
    date_string
    |> String.trim()
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.replace(",", ", ")  # Normalize comma spacing
  end

  defp parse_date_range(date_string) do
    case String.split(date_string, " - ", parts: 2) do
      [start_str, end_str] ->
        with {:ok, start_date} <- parse_single_date(start_str),
             {:ok, end_date} <- parse_single_date(end_str) do
          {:ok, {start_date, end_date}}
        else
          _ -> {:error, :invalid_range}
        end

      _ ->
        {:error, :invalid_range}
    end
  end

  defp parse_date_range_with_time(date_string) do
    # Handle formats like "04.09.2025, 18:00 - 25.09.2025"
    case Regex.run(~r/(\d{1,2}\.\d{1,2}\.\d{4}),?\s*(\d{1,2}:\d{2})?\s*-\s*(\d{1,2}\.\d{1,2}\.\d{4})/, date_string) do
      [_, start_date, time, end_date] ->
        with {:ok, start_dt} <- parse_single_date(start_date <> " " <> (time || "00:00")),
             {:ok, end_dt} <- parse_single_date(end_date) do
          {:ok, {start_dt, end_dt}}
        else
          _ -> {:error, :invalid_range}
        end

      _ ->
        # Try parsing as Polish date range
        parse_polish_date_range(date_string)
    end
  end

  defp parse_polish_date_range(date_string) do
    # Handle: "środa, 3 września 2025, 10:00 - wtorek, 30 września 2025"
    # Also handle: "czwartek, 4 września 2025 - czwartek, 9 października 2025"
    parts = String.split(date_string, " - ", parts: 2)

    case parts do
      [start_str, end_str] ->
        # Clean up the date parts - remove day names for easier parsing
        clean_start = clean_polish_date(start_str)
        clean_end = clean_polish_date(end_str)

        # Parse each part separately
        start_result = cond do
          String.match?(clean_start, ~r/\d+\s+\w+\s+\d{4}/u) ->
            parse_polish_date(clean_start)
          String.match?(clean_start, ~r/\d{1,2}\.\d{1,2}\.\d{4}/) ->
            parse_standard_date(clean_start)
          true ->
            {:error, :unknown_format}
        end

        end_result = cond do
          String.match?(clean_end, ~r/\d+\s+\w+\s+\d{4}/u) ->
            parse_polish_date(clean_end)
          String.match?(clean_end, ~r/\d{1,2}\.\d{1,2}\.\d{4}/) ->
            parse_standard_date(clean_end)
          true ->
            {:error, :unknown_format}
        end

        case {start_result, end_result} do
          {{:ok, {start_dt, _}}, {:ok, {end_dt, _}}} ->
            {:ok, {start_dt, end_dt}}
          {{:ok, {start_dt, _}}, _} ->
            # If we can't parse the end date, use start date + 1 day as fallback
            {:ok, {start_dt, DateTime.add(start_dt, 86400, :second)}}
          _ ->
            {:error, :invalid_range}
        end

      _ ->
        parse_date_range(date_string)
    end
  end

  defp clean_polish_date(date_str) do
    # Remove Polish day names to make parsing easier
    date_str
    |> String.replace(~r/^(poniedziałek|wtorek|środa|czwartek|piątek|sobota|niedziela),?\s*/iu, "")
    |> String.trim()
  end

  defp parse_polish_date(date_string) do
    # Parse "czwartek, 4 września 2025, 18:00"
    case Regex.run(~r/(\d{1,2})\s+([a-ząćęłńóśźż]+)\s+(\d{4})(?:,?\s*(\d{1,2}:\d{2}))?/iu, date_string) do
      [_, day, month_name, year] ->
        parse_polish_date_parts(day, month_name, year, nil)

      [_, day, month_name, year, time] ->
        parse_polish_date_parts(day, month_name, year, time)

      _ ->
        {:error, :invalid_polish_date}
    end
  end

  defp parse_polish_date_parts(day_str, month_name, year_str, time_str) do
    month = @polish_months[String.downcase(month_name)]

    if month do
      day = String.to_integer(day_str)
      year = String.to_integer(year_str)

      {hour, minute} = if time_str do
        parse_time(time_str)
      else
        {0, 0}
      end

      case DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, 0)) do
        {:ok, datetime} ->
          {:ok, {datetime, datetime}}  # Single date, not a range

        {:error, reason} ->
          {:error, reason}
      end
    else
      Logger.warning("Unknown Polish month: #{month_name}")
      {:error, :unknown_month}
    end
  end

  defp parse_standard_date(date_string) do
    # Parse "04.09.2025" or "04.09.2025, 18:00"
    case Regex.run(~r/(\d{1,2})\.(\d{1,2})\.(\d{4})(?:,?\s*(\d{1,2}:\d{2}))?/, date_string) do
      [_, day, month, year] ->
        create_datetime(year, month, day, nil)

      [_, day, month, year, time] ->
        create_datetime(year, month, day, time)

      _ ->
        {:error, :invalid_date}
    end
  end

  defp parse_iso_date(date_string) do
    # Parse "2025-09-04" or "2025-09-04T18:00:00"
    case DateTime.from_iso8601(date_string <> "Z") do
      {:ok, datetime, _} ->
        {:ok, {datetime, datetime}}

      _ ->
        case Date.from_iso8601(date_string) do
          {:ok, date} ->
            {:ok, datetime} = DateTime.new(date, Time.new!(0, 0, 0))
            {:ok, {datetime, datetime}}

          _ ->
            {:error, :invalid_iso_date}
        end
    end
  end

  defp parse_single_date(date_str) do
    date_str = String.trim(date_str)

    cond do
      Regex.match?(~r/\d{1,2}\.\d{1,2}\.\d{4}/, date_str) ->
        case parse_standard_date(date_str) do
          {:ok, {datetime, _}} -> {:ok, datetime}
          error -> error
        end

      Regex.match?(~r/\d{4}-\d{2}-\d{2}/, date_str) ->
        case parse_iso_date(date_str) do
          {:ok, {datetime, _}} -> {:ok, datetime}
          error -> error
        end

      true ->
        {:error, :unknown_format}
    end
  end

  defp create_datetime(year_str, month_str, day_str, time_str) do
    year = String.to_integer(year_str)
    month = String.to_integer(month_str)
    day = String.to_integer(day_str)

    {hour, minute} = if time_str do
      parse_time(time_str)
    else
      {0, 0}
    end

    case DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, 0)) do
      {:ok, datetime} ->
        {:ok, {datetime, datetime}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :invalid_date}
  end

  defp parse_time(time_str) do
    case Regex.run(~r/(\d{1,2}):(\d{2})/, time_str) do
      [_, hour, minute] ->
        {String.to_integer(hour), String.to_integer(minute)}

      _ ->
        {0, 0}
    end
  end

  @doc """
  Extract start datetime from a date string.
  Convenience function that returns just the start date.
  """
  def parse_start_date(date_string) do
    case parse_date_string(date_string) do
      {:ok, {start_dt, _}} -> start_dt
      _ -> nil
    end
  end

  @doc """
  Extract end datetime from a date string.
  Convenience function that returns just the end date.
  """
  def parse_end_date(date_string) do
    case parse_date_string(date_string) do
      {:ok, {_, end_dt}} -> end_dt
      _ -> nil
    end
  end
end