defmodule EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.Polish do
  @moduledoc """
  Polish language date pattern provider for multilingual date parser.

  Supports various Polish date formats commonly found in event listings:
  - Numeric dates: "04.09.2025" (DD.MM.YYYY format)
  - Numeric date ranges: "04.09.2025 - 09.10.2025"
  - Single dates with day names: "poniedziałek, 3 listopada 2025"
  - Single dates without day names: "3 listopada 2025"
  - Date ranges: "od 19 marca do 21 marca 2025"
  - Times: "18:00", "Godzina rozpoczęcia: 18:00", "o godz. 18:00"

  ## Examples

      iex> Polish.extract_components("04.09.2025")
      {:ok, %{type: :single, day: 4, month: 9, year: 2025}}

      iex> Polish.extract_components("04.09.2025 - 09.10.2025")
      {:ok, %{
        type: :range_cross_year,
        start_day: 4,
        start_month: 9,
        start_year: 2025,
        end_day: 9,
        end_month: 10,
        end_year: 2025
      }}

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

      iex> Polish.extract_components("środa, 5 listopada 2025 ⌚ Godzina rozpoczęcia: 18:00")
      {:ok, %{type: :single, day: 5, month: 11, year: 2025, hour: 18, minute: 0}}
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
      # DD.MM.YYYY date range: "04.09.2025 - 09.10.2025"
      # Must come before text patterns to match numeric dates first
      ~r/(\d{1,2})\.(\d{1,2})\.(\d{4})\s*-\s*(\d{1,2})\.(\d{1,2})\.(\d{4})/u,

      # DD.MM.YYYY single date: "04.09.2025"
      # Must come before text patterns to match numeric dates first
      ~r/(\d{1,2})\.(\d{1,2})\.(\d{4})/u,

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
    result =
      Enum.reduce_while(patterns(), {:error, :no_match}, fn pattern, acc ->
        case Regex.run(pattern, normalized) do
          nil ->
            # Pattern doesn't match - preserve accumulator (might have validation error from previous pattern)
            {:cont, acc}

          matches ->
            case parse_matches(matches, pattern, normalized) do
              {:ok, components} ->
                Logger.debug("✅ Polish parser: Extracted #{inspect(components)}")
                {:halt, {:ok, components}}

              {:error, _} = error ->
                # Pattern matched but validation failed - continue with this error
                {:cont, error}
            end
        end
      end)

    # If we extracted date components, also try to extract time
    case result do
      {:ok, components} ->
        time_components = extract_time(text)
        {:ok, Map.merge(components, time_components)}

      error ->
        error
    end
  end

  # Private functions

  # Parse regex matches based on the pattern that matched
  defp parse_matches(matches, pattern, _original_text) do
    # Get the source of the pattern to check what kind of pattern it is
    source = Regex.source(pattern)

    cond do
      # DD.MM.YYYY date range: [full, day1, month1, year1, day2, month2, year2]
      # E.g., "04.09.2025 - 09.10.2025"
      # Check if pattern source contains "\." (escaped dot) which indicates numeric format
      length(matches) == 7 and String.contains?(source, "\\.") ->
        [_, start_day, start_month, start_year, end_day, end_month, end_year] = matches

        with {start_day_int, _} <- Integer.parse(start_day),
             {end_day_int, _} <- Integer.parse(end_day),
             {start_month_int, _} <- Integer.parse(start_month),
             {end_month_int, _} <- Integer.parse(end_month),
             {start_year_int, _} <- Integer.parse(start_year),
             {end_year_int, _} <- Integer.parse(end_year),
             true <- valid_date?(start_day_int, start_month_int, start_year_int),
             true <- valid_date?(end_day_int, end_month_int, end_year_int) do
          {:ok,
           %{
             type: :range_cross_year,
             start_day: start_day_int,
             start_month: start_month_int,
             start_year: start_year_int,
             end_day: end_day_int,
             end_month: end_month_int,
             end_year: end_year_int
           }}
        else
          _ -> {:error, :invalid_date_components}
        end

      # DD.MM.YYYY single date: [full, day, month, year]
      # E.g., "04.09.2025"
      # Distinguished from text month patterns by checking if month can be parsed as integer
      length(matches) == 4 ->
        [_, day, month, year] = matches

        # Try to parse month as integer first (DD.MM.YYYY format)
        case Integer.parse(month) do
          {month_int, ""} ->
            # Month is numeric - this is DD.MM.YYYY format
            with {day_int, _} <- Integer.parse(day),
                 {year_int, _} <- Integer.parse(year),
                 true <- valid_date?(day_int, month_int, year_int) do
              {:ok, %{type: :single, day: day_int, month: month_int, year: year_int}}
            else
              _ -> {:error, :invalid_date_components}
            end

          _ ->
            # Month is text - this is text format (e.g., "3 listopada 2025")
            with {day_int, _} <- Integer.parse(day),
                 {year_int, _} <- Integer.parse(year),
                 {:ok, month_num} <- validate_month(month) do
              {:ok, %{type: :single, day: day_int, month: month_num, year: year_int}}
            else
              _ -> {:error, :invalid_date_components}
            end
        end

      # Date range cross-year: [full, day1, month1, year1, day2, month2, year2]
      length(matches) == 7 and String.contains?(source, "do") ->
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
      length(matches) == 6 and String.contains?(source, "do") ->
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
      length(matches) == 5 and String.contains?(source, "do") ->
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

  # Validate date components (day, month, year)
  defp valid_date?(day, month, year) do
    day >= 1 and day <= 31 and
      month >= 1 and month <= 12 and
      year >= 1900 and year <= 2100
  end

  # Extract time components from text
  # Supports Polish time formats:
  # - "Godzina rozpoczęcia: 18:00"
  # - "o godz. 18:00"
  # - "18:00" (standalone)
  # - "18.00" (dot separator)
  defp extract_time(text) when is_binary(text) do
    time_patterns = [
      # "Godzina rozpoczęcia: 18:00" or "Godzina: 18:00"
      ~r/godzin[aą](?:\s+rozpoczęcia)?:\s*(\d{1,2})[:\.](\d{2})/iu,
      # "o godz. 18:00"
      ~r/o\s+godz\.?\s*(\d{1,2})[:\.](\d{2})/iu,
      # Standalone time "18:00" or "18.00" - must not be followed by more digits (to avoid matching dates)
      # Also ensures we're matching actual time values (hours 0-23)
      ~r/(?:^|\s|,)\s*(\d{1,2})[:\.](\d{2})(?!\.\d)/u
    ]

    # Try each time pattern
    Enum.reduce_while(time_patterns, %{}, fn pattern, _acc ->
      case Regex.run(pattern, text) do
        [_, hour_str, minute_str] ->
          with {hour, _} <- Integer.parse(hour_str),
               {minute, _} <- Integer.parse(minute_str),
               true <- hour >= 0 and hour <= 23,
               true <- minute >= 0 and minute <= 59 do
            Logger.debug("⏰ Polish parser: Extracted time #{hour}:#{minute}")
            {:halt, %{hour: hour, minute: minute}}
          else
            _ ->
              Logger.debug("⚠️ Polish parser: Invalid time components in '#{text}'")
              {:cont, %{}}
          end

        _ ->
          {:cont, %{}}
      end
    end)
  end
end
