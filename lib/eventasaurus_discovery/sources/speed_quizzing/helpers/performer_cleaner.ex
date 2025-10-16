defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Helpers.PerformerCleaner do
  @moduledoc """
  Utilities for cleaning and normalizing performer/host names from Speed Quizzing.

  Speed Quizzing performer names often include rating prefixes like:
  - "★234 Matt Lavery" → "Matt Lavery"
  - "⭐️123 DJ John Smith" → "DJ John Smith"

  This module handles extraction and normalization of these names by:
  1. Removing star/emoji rating prefixes (★234, ⭐️123)
  2. Normalizing DJ prefixes
  3. Trimming whitespace
  """

  require Logger

  @doc """
  Cleans a performer name by removing rating prefixes and normalizing formatting.

  ## Examples
      iex> clean_name("★234 Matt Lavery")
      "Matt Lavery"

      iex> clean_name("DJ John Smith")
      "DJ John Smith"

      iex> clean_name(nil)
      nil
  """
  def clean_name(nil), do: nil
  def clean_name(""), do: ""

  def clean_name(name) when is_binary(name) do
    Logger.debug("[SpeedQuizzing] Processing performer name: '#{name}'")

    # Log if star pattern is found
    if String.match?(name, ~r/★\d+/) do
      [_, digits] = Regex.run(~r/★(\d+)/, name)
      Logger.debug("[SpeedQuizzing] Found star-number pattern: #{digits}")
    end

    # Remove star-number prefixes like "★234 Matt Lavery"
    cleaned =
      case Regex.run(~r/^★\d+\s+(.+)$/, name) do
        [_, real_name] ->
          Logger.debug("[SpeedQuizzing] Extracted name after star prefix: '#{real_name}'")
          real_name

        _ ->
          # Try more general pattern for other emoji/symbols
          case Regex.run(~r/^[^\w\s]\d+\s+(.+)$/, name) do
            [_, real_name] -> real_name
            _ -> name
          end
      end

    # Normalize DJ prefix spacing
    final =
      cleaned
      |> String.replace(~r/^DJ\s+/, "DJ ")
      |> String.trim()

    Logger.debug("[SpeedQuizzing] Final cleaned name: '#{final}'")
    final
  end
end
