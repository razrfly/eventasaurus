defmodule EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.French do
  @moduledoc """
  French language date pattern provider for multilingual date parser.

  Supports various French date formats commonly found in event listings:
  - Single dates: "17 octobre 2025", "vendredi 31 octobre 2025", "Le 19 avril 2025"
  - Date ranges: "Du 1er janvier au 15 février 2026", "15 octobre au 20 novembre 2025"
  - With ordinals: "1er janvier 2026", "2e mars 2025"

  ## Examples

      iex> French.extract_components("17 octobre 2025")
      {:ok, %{type: :single, day: 17, month: "octobre", year: 2025}}

      iex> French.extract_components("du 1er janvier au 15 février 2026")
      {:ok, %{
        type: :range,
        start_day: 1,
        start_month: "janvier",
        end_day: 15,
        end_month: "février",
        year: 2026
      }}
  """

  @behaviour EventasaurusDiscovery.Sources.Shared.Parsers.DatePatternProvider

  require Logger

  @impl true
  def month_names do
    %{
      # Full month names
      "janvier" => 1,
      "février" => 2,
      "mars" => 3,
      "avril" => 4,
      "mai" => 5,
      "juin" => 6,
      "juillet" => 7,
      "août" => 8,
      "septembre" => 9,
      "octobre" => 10,
      "novembre" => 11,
      "décembre" => 12,
      # Abbreviated month names
      "janv" => 1,
      "févr" => 2,
      "avr" => 4,
      "juil" => 7,
      "sept" => 9,
      "déc" => 12
    }
  end

  @impl true
  def patterns do
    months = Enum.join(Map.keys(month_names()), "|")

    [
      # Date range cross-month: "du 19 mars au 7 juillet 2025", "Du 1er janvier au 15 février 2026"
      ~r/\b(?:du|from)?\s*(\d{1,2})(?:er|e)?\s+(#{months})\s+au\s+(\d{1,2})(?:er|e)?\s+(#{months})\s+(\d{4})\b/i,

      # Date range same month: "du 15 au 20 octobre 2025", "15 octobre au 20 novembre 2025"
      ~r/\b(?:du)?\s*(\d{1,2})(?:er|e)?\s+au\s+(\d{1,2})(?:er|e)?\s+(#{months})\s+(\d{4})\b/i,

      # Date range same month alternative: "15 au 20 octobre 2025"
      ~r/\b(\d{1,2})(?:er|e)?\s+au\s+(\d{1,2})(?:er|e)?\s+(#{months})\s+(\d{4})\b/i,

      # Single date: "17 octobre 2025", "1er janvier 2026", "Le 19 avril 2025"
      ~r/\b(?:le\s+)?(\d{1,2})(?:er|e)?\s+(#{months})\s+(\d{4})\b/i,

      # Month and year only: "octobre 2025"
      ~r/\b(#{months})\s+(\d{4})\b/i
    ]
  end

  @impl true
  def extract_components(text) when is_binary(text) do
    # Normalize: lowercase, strip day names, clean whitespace
    normalized = normalize_text(text)

    Logger.debug("🇫🇷 French parser: Processing '#{normalized}'")

    # Try each pattern in order
    Enum.reduce_while(patterns(), {:error, :no_match}, fn pattern, _acc ->
      case Regex.run(pattern, normalized) do
        nil ->
          {:cont, {:error, :no_match}}

        matches ->
          case parse_matches(matches, pattern, normalized) do
            {:ok, components} ->
              Logger.debug("✅ French parser: Extracted #{inspect(components)}")
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
      # Date range cross-month: [full, day1, month1, day2, month2, year]
      length(matches) == 6 and Regex.match?(~r/au/i, Regex.source(pattern)) ->
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
      length(matches) == 5 and Regex.match?(~r/au/i, Regex.source(pattern)) ->
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
    |> strip_day_names()
    |> strip_articles()
    |> String.replace(",", " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Strip French day names (lundi, mardi, etc.)
  defp strip_day_names(text) do
    day_names = ~w(
      lundi mardi mercredi jeudi vendredi samedi dimanche
      lun mar mer jeu ven sam dim
    )

    Enum.reduce(day_names, text, fn day_name, acc ->
      String.replace(acc, ~r/\b#{day_name}\b/i, "")
    end)
  end

  # Strip French articles (Le, Du, La)
  defp strip_articles(text) do
    text
    |> String.replace(~r/\b(le|la|du|de|l')\b/i, "")
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
