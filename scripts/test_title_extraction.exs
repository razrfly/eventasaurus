# Test script for Cinema City original title extraction
# Run with: mix run test_title_extraction.exs

defmodule TitleExtractionTest do
  @moduledoc """
  Test the original title extraction logic from Cinema City mixed-language titles.
  """

  # Simulate the extraction function (same logic as in MovieDetailJob)
  defp extract_original_title(polish_title, %{"original_language" => "en"}) when is_binary(polish_title) do
    separators = [". ", ": ", " - ", " – ", " — "]

    Enum.reduce_while(separators, nil, fn separator, _acc ->
      case String.split(polish_title, separator, parts: 2) do
        [original_part, _polish_part] ->
          {:halt, String.trim(original_part)}
        _ ->
          {:cont, nil}
      end
    end)
  end

  defp extract_original_title(_polish_title, _language_info), do: nil

  def test_extraction do
    IO.puts("\n=== Testing Cinema City Original Title Extraction ===\n")

    test_cases = [
      # Case 1: The failing example from Job #9252
      %{
        polish_title: "Eternity. Wybieram ciebie",
        language_info: %{"original_language" => "en", "is_subbed" => true},
        expected: "Eternity"
      },
      # Case 2: Another common pattern
      %{
        polish_title: "The Substance. Substancja",
        language_info: %{"original_language" => "en", "is_subbed" => true},
        expected: "The Substance"
      },
      # Case 3: Title with colon separator
      %{
        polish_title: "Dune: Part Two",
        language_info: %{"original_language" => "en", "is_subbed" => true},
        expected: nil  # No separator after colon
      },
      # Case 4: Title with dash separator
      %{
        polish_title: "Nosferatu - Symfonia grozy",
        language_info: %{"original_language" => "en", "is_subbed" => true},
        expected: "Nosferatu"
      },
      # Case 5: Polish-only film (no original_language)
      %{
        polish_title: "Zimna wojna",
        language_info: %{},
        expected: nil
      },
      # Case 6: French film (original_language not "en")
      %{
        polish_title: "Amelie. Amélie",
        language_info: %{"original_language" => "fr", "is_subbed" => true},
        expected: nil
      }
    ]

    Enum.each(test_cases, fn test_case ->
      result = extract_original_title(test_case.polish_title, test_case.language_info)
      status = if result == test_case.expected, do: "✅ PASS", else: "❌ FAIL"

      IO.puts("#{status}")
      IO.puts("  Polish Title: #{test_case.polish_title}")
      IO.puts("  Original Language: #{inspect(test_case.language_info["original_language"])}")
      IO.puts("  Expected: #{inspect(test_case.expected)}")
      IO.puts("  Got: #{inspect(result)}")
      IO.puts("")
    end)

    IO.puts("=== Test Complete ===\n")
  end

  def test_with_tmdb_search do
    IO.puts("\n=== Testing with TMDB Search Simulation ===\n")

    # Simulate what would happen with the extracted title
    test_case = %{
      polish_title: "Eternity. Wybieram ciebie",
      language_info: %{"original_language" => "en", "is_subbed" => true},
      year: 2025
    }

    extracted = extract_original_title(test_case.polish_title, test_case.language_info)

    IO.puts("Original mixed title: #{test_case.polish_title}")
    IO.puts("Extracted original: #{inspect(extracted)}")
    IO.puts("\nTmdbMatcher would now search:")
    IO.puts("  Strategy 1: \"#{extracted}\" + #{test_case.year} in ENGLISH")
    IO.puts("  (Should find TMDB match for 'Eternity (2025)')")
    IO.puts("")
  end
end

# Run the tests
TitleExtractionTest.test_extraction()
TitleExtractionTest.test_with_tmdb_search()
