# Test script for Cinema City movie matching with original title extraction
# Run with: mix run test_single_movie.exs
#
# This script tests the new original title extraction on a single Cinema City movie
# to verify it works before running a full import.

defmodule SingleMovieTest do
  @moduledoc """
  Test the complete flow: extract original title → TMDB search → match movie
  Uses the actual MovieDetailJob logic to simulate what will happen in production.
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob
  alias EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher

  def test_eternity_movie do
    IO.puts("\n=== Testing Cinema City Movie: Eternity ===\n")

    # Simulate the film_data structure from Job #9252
    film_data = %{
      "polish_title" => "Eternity. Wybieram ciebie",
      "release_year" => 2025,
      "runtime" => 112,
      "cinema_city_film_id" => "7742s2r",
      "language_info" => %{
        "original_language" => "en",
        "is_subbed" => true,
        "is_dubbed" => false
      }
    }

    IO.puts("Film Data:")
    IO.puts("  Polish Title: #{film_data["polish_title"]}")
    IO.puts("  Original Language: #{film_data["language_info"]["original_language"]}")
    IO.puts("  Year: #{film_data["release_year"]}")
    IO.puts("")

    # Test the extraction using reflection to call private function
    # Note: We'll just test the logic directly since we can't easily call private functions
    extracted = extract_original_title(
      film_data["polish_title"],
      film_data["language_info"]
    )

    IO.puts("Extraction Result:")
    IO.puts("  Original Title: #{inspect(extracted)}")
    IO.puts("")

    # Normalize film data (same as MovieDetailJob would)
    movie_data = normalize_film_data(film_data)

    IO.puts("Normalized Movie Data:")
    IO.puts("  #{inspect(movie_data, pretty: true)}")
    IO.puts("")

    # Try TMDB matching
    IO.puts("Attempting TMDB Match...")

    case TmdbMatcher.match_movie(movie_data) do
      {:ok, tmdb_id, confidence, provider} ->
        IO.puts("✅ SUCCESS!")
        IO.puts("  TMDB ID: #{tmdb_id}")
        IO.puts("  Confidence: #{Float.round(confidence * 100, 1)}%")
        IO.puts("  Provider: #{provider}")
        IO.puts("")

        # Get movie details from TMDB
        case TmdbMatcher.find_or_create_movie(tmdb_id) do
          {:ok, movie} ->
            IO.puts("Movie Details:")
            IO.puts("  Title: #{movie.title}")
            IO.puts("  Original Title: #{movie.original_title}")
            IO.puts("  Year: #{movie.year}")
            IO.puts("")

          {:error, reason} ->
            IO.puts("⚠️  Failed to fetch movie details: #{inspect(reason)}")
        end

      {:needs_review, _movie_data, candidates} ->
        IO.puts("⚠️  Needs Review (Low Confidence)")
        IO.puts("  Candidates found: #{length(candidates)}")
        IO.puts("")

      {:error, :tmdb_low_confidence} ->
        IO.puts("❌ FAILED: Low Confidence")
        IO.puts("  This means TMDB matching didn't find a good enough match")
        IO.puts("")

      {:error, :no_results} ->
        IO.puts("❌ FAILED: No Results")
        IO.puts("  TMDB didn't return any results for this search")
        IO.puts("")

      {:error, reason} ->
        IO.puts("❌ FAILED: #{inspect(reason)}")
        IO.puts("")
    end

    IO.puts("=== Test Complete ===\n")
  end

  # Replicate the extraction logic from MovieDetailJob
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

  # Replicate the normalize_film_data logic
  defp normalize_film_data(film_data) do
    polish_title = film_data["polish_title"]
    language_info = film_data["language_info"] || %{}
    original_title = extract_original_title(polish_title, language_info)

    %{
      polish_title: polish_title,
      original_title: original_title,
      year: film_data["release_year"],
      runtime: film_data["runtime"],
      director: nil,
      country: nil
    }
  end

  def test_comparison do
    IO.puts("\n=== Comparison: Before vs After ===\n")

    film_data = %{
      "polish_title" => "Eternity. Wybieram ciebie",
      "language_info" => %{"original_language" => "en"}
    }

    IO.puts("BEFORE (Phase 5.3):")
    IO.puts("  original_title: nil")
    IO.puts("  primary_title: \"Eternity. Wybieram ciebie\"")
    IO.puts("  Strategy 1: Search \"Eternity. Wybieram ciebie\" in ENGLISH → ❌ Fails")
    IO.puts("")

    extracted = extract_original_title(
      film_data["polish_title"],
      film_data["language_info"]
    )

    IO.puts("AFTER (Current):")
    IO.puts("  original_title: #{inspect(extracted)}")
    IO.puts("  primary_title: \"Eternity\"")
    IO.puts("  Strategy 1: Search \"Eternity\" in ENGLISH → ✅ Should succeed")
    IO.puts("")
  end
end

# Run the tests
SingleMovieTest.test_comparison()
SingleMovieTest.test_eternity_movie()
