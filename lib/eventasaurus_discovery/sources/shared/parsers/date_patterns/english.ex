defmodule EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.English do
  @moduledoc """
  English language date pattern provider for multilingual date parser.

  Supports various English date formats commonly found in event listings:
  - Single dates: "October 15, 2025", "Friday, October 31, 2025"
  - Date ranges: "October 15, 2025 to January 19, 2026", "October 15 to November 20, 2025"
  - With ordinals: "October 1st, 2025", "March 3rd, 2025"

  ## Examples

      iex> English.extract_components("October 15, 2025")
      {:ok, %{type: :single, day: 15, month: "october", year: 2025}}

      iex> English.extract_components("October 15, 2025 to January 19, 2026")
      {:ok, %{
        type: :range,
        start_day: 15,
        start_month: "october",
        end_day: 19,
        end_month: "january",
        year: 2026
      }}
  """

  @behaviour EventasaurusDiscovery.Sources.Shared.Parsers.DatePatternProvider

  require Logger

  @impl true
  def month_names do
    %{
      # Full month names
      "january" => 1,
      "february" => 2,
      "march" => 3,
      "april" => 4,
      "may" => 5,
      "june" => 6,
      "july" => 7,
      "august" => 8,
      "september" => 9,
      "october" => 10,
      "november" => 11,
      "december" => 12,
      # Abbreviated month names
      "jan" => 1,
      "feb" => 2,
      "mar" => 3,
      "apr" => 4,
      "jun" => 6,
      "jul" => 7,
      "aug" => 8,
      "sep" => 9,
      "oct" => 10,
      "nov" => 11,
      "dec" => 12
    }
  end

  @impl true
  def patterns do
    months = Enum.join(Map.keys(month_names()), "|")

    [
      # Date range with full dates: "October 15, 2025 to January 19, 2026"
      ~r/\b(#{months})\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\s+to\s+(#{months})\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b/i,

      # Date range same year: "October 15 to November 20, 2025"
      ~r/\b(#{months})\s+(\d{1,2})(?:st|nd|rd|th)?\s+to\s+(#{months})\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b/i,

      # Date range same month: "October 15 to 20, 2025"
      ~r/\b(#{months})\s+(\d{1,2})(?:st|nd|rd|th)?\s+to\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b/i,

      # Single date with comma: "October 15, 2025", "Friday, October 31, 2025"
      ~r/\b(#{months})\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b/i,

      # Single date without comma: "October 15 2025"
      ~r/\b(#{months})\s+(\d{1,2})(?:st|nd|rd|th)?\s+(\d{4})\b/i,

      # Month and year only: "October 2025"
      ~r/\b(#{months})\s+(\d{4})\b/i
    ]
  end

  @impl true
  def extract_components(text) when is_binary(text) do
    # Normalize: lowercase, strip day names, clean whitespace
    normalized = normalize_text(text)

    Logger.debug("🇬🇧 English parser: Processing '#{normalized}'")

    # Try each pattern in order
    Enum.reduce_while(patterns(), {:error, :no_match}, fn pattern, _acc ->
      case Regex.run(pattern, normalized) do
        nil ->
          {:cont, {:error, :no_match}}

        matches ->
          case parse_matches(matches, pattern, normalized) do
            {:ok, components} ->
              Logger.debug("✅ English parser: Extracted #{inspect(components)}")
              {:halt, {:ok, components}}

            {:error, _} = error ->
              {:cont, error}
          end
      end
    end)
  end

  # Private functions

  # Parse regex matches based on the pattern that matched
  defp parse_matches(matches, pattern, _original_text) do
    cond do
      # Date range with full dates: [full, month1, day1, year1, month2, day2, year2]
      length(matches) == 7 and Regex.match?(~r/to.*to/i, Regex.source(pattern)) ->
        [_, start_month, start_day, start_year, end_month, end_day, end_year] = matches

        with {start_day_int, _} <- Integer.parse(start_day),
             {_start_year_int, _} <- Integer.parse(start_year),
             {end_day_int, _} <- Integer.parse(end_day),
             {end_year_int, _} <- Integer.parse(end_year),
             {:ok, start_month_num} <- validate_month(start_month),
             {:ok, end_month_num} <- validate_month(end_month) do
          {:ok,
           %{
             type: :range,
             start_day: start_day_int,
             start_month: start_month_num,
             end_day: end_day_int,
             end_month: end_month_num,
             year: end_year_int
           }}
        else
          _ -> {:error, :invalid_date_components}
        end

      # Date range same year: [full, month1, day1, month2, day2, year]
      length(matches) == 6 and Regex.match?(~r/to/i, Regex.source(pattern)) ->
        [_, start_month, start_day, end_month, end_day, year] = matches

        with {start_day_int, _} <- Integer.parse(start_day),
             {end_day_int, _} <- Integer.parse(end_day),
             {year_int, _} <- Integer.parse(year),
             {:ok, start_month_num} <- validate_month(start_month),
             {:ok, end_month_num} <- validate_month(end_month) do
          {:ok,
           %{
             type: :range,
             start_day: start_day_int,
             start_month: start_month_num,
             end_day: end_day_int,
             end_month: end_month_num,
             year: year_int
           }}
        else
          _ -> {:error, :invalid_date_components}
        end

      # Date range same month: [full, month, day1, day2, year]
      length(matches) == 5 and Regex.match?(~r/to/i, Regex.source(pattern)) ->
        [_, month, start_day, end_day, year] = matches

        with {start_day_int, _} <- Integer.parse(start_day),
             {end_day_int, _} <- Integer.parse(end_day),
             {year_int, _} <- Integer.parse(year),
             {:ok, month_num} <- validate_month(month) do
          {:ok,
           %{
             type: :range,
             start_day: start_day_int,
             end_day: end_day_int,
             month: month_num,
             year: year_int
           }}
        else
          _ -> {:error, :invalid_date_components}
        end

      # Single date: [full, month, day, year]
      length(matches) == 4 ->
        [_, month, day, year] = matches

        with {day_int, _} <- Integer.parse(day),
             {year_int, _} <- Integer.parse(year),
             {:ok, month_num} <- validate_month(month) do
          {:ok, %{type: :single, day: day_int, month: month_num, year: year_int}}
        else
          _ -> {:error, :invalid_date_components}
        end

      # Month and year only: [full, month, year]
      length(matches) == 3 ->
        [_, month, year] = matches

        with {year_int, _} <- Integer.parse(year),
             {:ok, month_num} <- validate_month(month) do
          {:ok, %{type: :month, month: month_num, year: year_int}}
        else
          _ -> {:error, :invalid_date_components}
        end

      true ->
        {:error, :unrecognized_pattern}
    end
  end

  # Normalize text for parsing
  defp normalize_text(text) do
    text
    |> String.downcase()
    |> strip_day_names()
    |> strip_articles()
    |> String.replace(",", " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Strip English day names (Monday, Tuesday, etc.)
  defp strip_day_names(text) do
    day_names = ~w(
      monday tuesday wednesday thursday friday saturday sunday
      mon tue wed thu fri sat sun
    )

    Enum.reduce(day_names, text, fn day_name, acc ->
      String.replace(acc, ~r/\b#{day_name}\b/i, "")
    end)
  end

  # Strip English articles (The, From, On)
  defp strip_articles(text) do
    text
    |> String.replace(~r/\b(the|from|on)\b/i, "")
    |> String.trim()
  end

  # Validate month name and return month number
  defp validate_month(month_name) when is_binary(month_name) do
    normalized_name = String.downcase(month_name)

    case Map.get(month_names(), normalized_name) do
      nil -> {:error, :invalid_month}
      month_num -> {:ok, month_num}
    end
  end
end
