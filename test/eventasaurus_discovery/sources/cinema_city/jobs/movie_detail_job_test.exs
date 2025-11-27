defmodule EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJobTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob

  describe "extract_original_title/2" do
    test "extracts original English title with period separator" do
      # Given: Mixed-language title with period separator (". ")
      polish_title = "Eternity. Wybieram ciebie"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns English title before period
      assert result == "Eternity"
    end

    test "extracts original English title with colon separator" do
      # Given: Mixed-language title with colon separator (": ")
      polish_title = "Wicked: Na dobre"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns English title before colon
      assert result == "Wicked"
    end

    test "extracts original English title with dash separator" do
      # Given: Mixed-language title with dash separator (" - ")
      polish_title = "Gladiator - Wojownik"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns English title before dash
      assert result == "Gladiator"
    end

    test "extracts original English title with en dash separator" do
      # Given: Mixed-language title with en dash (" – ")
      polish_title = "Avatar – Droga wody"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns English title before en dash
      assert result == "Avatar"
    end

    test "extracts original English title with em dash separator" do
      # Given: Mixed-language title with em dash (" — ")
      polish_title = "Inception — Początek"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns English title before em dash
      assert result == "Inception"
    end

    test "trims whitespace from extracted title" do
      # Given: Title with extra whitespace
      polish_title = "  Dune  . Diuna  "
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns trimmed English title
      assert result == "Dune"
    end

    test "returns nil when original_language is not 'en'" do
      # Given: Polish-language film
      polish_title = "Uwierz w Mikołaja 2"
      language_info = %{"original_language" => "pl"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns nil (no extraction for non-English films)
      assert result == nil
    end

    test "returns nil when original_language is missing" do
      # Given: Film with no language info
      polish_title = "Psi patrol. Pieski ratują święta"
      language_info = %{}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns nil
      assert result == nil
    end

    test "returns nil when language_info is empty map" do
      # Given: Empty language info
      polish_title = "Some Title. Polski Tytuł"
      language_info = %{}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns nil
      assert result == nil
    end

    test "returns nil when title has no separator" do
      # Given: English film but title has no separator
      polish_title = "Zwierzogród 2"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns nil (no separator found)
      assert result == nil
    end

    test "returns nil when title only has separator without space" do
      # Given: Title has separator but no space after
      polish_title = "Title.PolishTitle"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns nil (separator must have space)
      assert result == nil
    end

    test "prefers period with space over other separators" do
      # Given: Title with multiple potential separators
      # Should split on ". " first, not ": " or " - "
      polish_title = "Title: Part 1. Polski Tytuł - Część 1"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns text before first ". " (not before ":")
      assert result == "Title: Part 1"
    end

    test "extracts only first part when title has multiple separators" do
      # Given: Title with multiple periods
      polish_title = "The Matrix. Reloaded. Matrix Reaktywacja"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns only first part
      assert result == "The Matrix"
    end

    test "handles empty string title" do
      # Given: Empty string
      polish_title = ""
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns nil
      assert result == nil
    end

    test "handles title with only separator" do
      # Given: Title is just a separator
      polish_title = ". "
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Returns empty string (trimmed)
      assert result == ""
    end

    test "preserves special characters in extracted title" do
      # Given: Title with special characters before separator
      polish_title = "Spider-Man: Into the Spider-Verse. Spider-Man: Uniwersum"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Preserves special characters (hyphen, colon) in extracted title
      # Note: Splits on ". " so returns full English title including colon part
      assert result == "Spider-Man: Into the Spider-Verse"
    end

    test "handles Unicode characters in title" do
      # Given: Title with Polish Unicode characters
      polish_title = "Interstellar. Międzygwiezdny"
      language_info = %{"original_language" => "en"}

      # When: Extract title
      result = MovieDetailJob.extract_original_title(polish_title, language_info)

      # Then: Correctly extracts English part
      assert result == "Interstellar"
    end
  end

  describe "extract_original_title/2 real-world examples from Phase 1 test" do
    test "extracts 'Wicked' from 'Wicked: Na dobre'" do
      assert MovieDetailJob.extract_original_title(
               "Wicked: Na dobre",
               %{"original_language" => "en"}
             ) == "Wicked"
    end

    test "extracts 'Eternity' from 'Eternity. Wybieram ciebie'" do
      assert MovieDetailJob.extract_original_title(
               "Eternity. Wybieram ciebie",
               %{"original_language" => "en"}
             ) == "Eternity"
    end

    test "returns nil for 'Zwierzogród 2' (no separator)" do
      assert MovieDetailJob.extract_original_title(
               "Zwierzogród 2",
               %{"original_language" => "en"}
             ) == nil
    end

    test "returns nil for 'Psi patrol. Pieski ratują święta' (no language info)" do
      assert MovieDetailJob.extract_original_title(
               "Psi patrol. Pieski ratują święta",
               %{}
             ) == nil
    end

    test "returns nil for 'Uwierz w Mikołaja 2' (Polish film)" do
      assert MovieDetailJob.extract_original_title(
               "Uwierz w Mikołaja 2",
               %{"original_language" => "pl"}
             ) == nil
    end

    test "returns nil for 'Bez przebaczenia' (no separator)" do
      assert MovieDetailJob.extract_original_title(
               "Bez przebaczenia",
               %{"original_language" => "en"}
             ) == nil
    end

    test "returns nil for 'Koszmarek' (no language info)" do
      assert MovieDetailJob.extract_original_title(
               "Koszmarek",
               nil
             ) == nil
    end
  end
end
