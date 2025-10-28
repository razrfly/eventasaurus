defmodule EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.Polish do
  @moduledoc """
  Polish language date pattern provider for multilingual date parser.

  Supports various Polish date formats commonly found in event listings:
  - Single dates with day names: "poniedziałek, 3 listopada 2025"
  - Single dates without day names: "3 listopada 2025"
  - Date ranges: "od 19 marca do 21 marca 2025"

  ## Examples

      iex> Polish.extract_components("poniedziałek, 3 listopada 2025")
      {:ok, %{type: :single, day: 3, month: "listopada", year: 2025}}

      iex> Polish.extract_components("od 19 marca do 21 marca 2025")
      {:ok, %{
        type: :range,
        start_day: 19,
        end_day: 21,
        month: "marca",
        year: 2025
      }}
  """

  @behaviour EventasaurusDiscovery.Sources.Shared.Parsers.DatePatternProvider

  require Logger

  @impl true
  def month_names do
    %{
      # Genitive case (most common in dates: "3 listopada")
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
      "grudnia" => 12,
      # Nominative case (month names on their own: "styczeń")
      "styczeń" => 1,
      "luty" => 2,
      "marzec" => 3,
      "kwiecień" => 4,
      "maj" => 5,
      "czerwiec" => 6,
      "lipiec" => 7,
      "sierpień" => 8,
      "wrzesień" => 9,
      "październik" => 10,
      "listopad" => 11,
      "grudzień" => 12,
      # Abbreviated forms
      "sty" => 1,
      "lut" => 2,
      "mar" => 3,
      "kwi" => 4,
      "cze" => 6,
      "lip" => 7,
      "sie" => 8,
      "wrz" => 9,
      "paź" => 10,
      "lis" => 11,
      "gru" => 12
    }
  end

  @impl true
  def patterns do
    # Escape and sort month tokens by length (longest first) for proper matching
    month_tokens =
      month_names()
      |> Map.keys()
      |> Enum.map(&Regex.escape/1)
      |> Enum.sort_by(&String.length/1, :desc)

    # Accept optional trailing "." for abbreviations
    months = "(?:" <> Enum.join(month_tokens, "|") <> ")\\.?"

    [
      # Date range cross-year: "od 29 grudnia 2025 do 2 stycznia 2026"
      ~r/\b(?:od\s*)?(\d{1,2})\s+(#{months})\s+(\d{4})\s+do\s+(\d{1,2})\s+(#{months})\s+(\d{4})\b/iu,

      # Date range cross-month (same year): "od 19 marca do 7 lipca 2025"
      ~r/\b(?:od\s*)?(\d{1,2})\s+(#{months})\s+do\s+(\d{1,2})\s+(#{months})\s+(\d{4})\b/iu,

      # Date range same month: "od 15 do 20 października 2025"
      ~r/\b(?:od\s*)?(\d{1,2})\s+do\s+(\d{1,2})\s+(#{months})\s+(\d{4})\b/iu,

      # Single date with day name: "poniedziałek, 3 listopada 2025"
      ~r/\b(?:poniedziałek|wtorek|środa|czwartek|piątek|sobota|niedziela),?\s*(\d{1,2})\s+(#{months})\s+(\d{4})\b/iu,

      # Single date without day name: "3 listopada 2025"
      ~r/\b(\d{1,2})\s+(#{months})\s+(\d{4})\b/iu,

      # Month and year only: "listopad 2025"
      ~r/\b(#{months})\s+(\d{4})\b/iu
    ]
  end

  @impl true
  def extract_components(text) when is_binary(text) do
    # Normalize: lowercase, clean whitespace
    normalized = normalize_text(text)

    Logger.debug("🇵🇱 Polish parser: Processing '#{normalized}'")

    # Try each pattern in order
    Enum.reduce_while(patterns(), {:error, :no_match}, fn pattern, _acc ->
      case Regex.run(pattern, normalized) do
        nil ->
          {:cont, {:error, :no_match}}

        matches ->
          case parse_matches(matches, pattern, normalized) do
            {:ok, components} ->
              Logger.debug("✅ Polish parser: Extracted #{inspect(components)}")
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
      # Date range cross-year: [full, day1, month1, year1, day2, month2, year2]
      length(matches) == 7 and Regex.match?(~r/do/i, Regex.source(pattern)) ->
        [_, start_day, start_month, start_year, end_day, end_month, end_year] = matches

        with {start_day_int, _} <- Integer.parse(start_day),
             {end_day_int, _} <- Integer.parse(end_day),
             {start_year_int, _} <- Integer.parse(start_year),
             {end_year_int, _} <- Integer.parse(end_year),
             {:ok, start_month_num} <- validate_month(start_month),
             {:ok, end_month_num} <- validate_month(end_month) do
          {:ok,
           %{
             type: :range_cross_year,
             start_day: start_day_int,
             start_month: start_month_num,
             start_year: start_year_int,
             end_day: end_day_int,
             end_month: end_month_num,
             end_year: end_year_int
           }}
        else
          _ -> {:error, :invalid_date_components}
        end

      # Date range cross-month: [full, day1, month1, day2, month2, year]
      length(matches) == 6 and Regex.match?(~r/do/i, Regex.source(pattern)) ->
        [_, start_day, start_month, end_day, end_month, year] = matches

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

      # Date range same month: [full, day1, day2, month, year]
      length(matches) == 5 and Regex.match?(~r/do/i, Regex.source(pattern)) ->
        [_, start_day, end_day, month, year] = matches

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

      # Single date: [full, day, month, year]
      length(matches) == 4 ->
        [_, day, month, year] = matches

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
    # Remove commas
    |> String.replace(",", " ")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Validate month name and return month number
  defp validate_month(month_name) when is_binary(month_name) do
    # Strip optional trailing "." and normalize
    normalized_name =
      month_name
      |> String.trim_trailing(".")
      |> String.downcase()

    case Map.get(month_names(), normalized_name) do
      nil -> {:error, :invalid_month}
      month_num -> {:ok, month_num}
    end
  end
end
