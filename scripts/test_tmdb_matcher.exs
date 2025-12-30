# Test actual TmdbMatcher.match_movie/1 on failed Cinema City movies
# Run with: mix run test_tmdb_matcher.exs

defmodule TmdbMatcherTest do
  @moduledoc """
  Test the actual TmdbMatcher logic on failed Cinema City movies.
  """

  alias EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher

  # The 7 unique failed movies from Cinema City
  @failed_movies [
    %{
      film_id: "7441s2r",
      polish_title: "Wicked: Na dobre",
      original_title: "Wicked",
      release_year: 2025,
      runtime: 137,
      original_language: "en"
    },
    %{
      film_id: "7381d2r",
      polish_title: "Zwierzogród 2",
      original_title: nil,
      release_year: 2025,
      runtime: 108,
      original_language: "en"
    },
    %{
      film_id: "7760d2r",
      polish_title: "Psi patrol. Pieski ratują święta",
      original_title: nil,
      release_year: 2025,
      runtime: 68,
      original_language: nil
    },
    %{
      film_id: "7671o2r",
      polish_title: "Uwierz w Mikołaja 2",
      original_title: nil,
      release_year: 2025,
      runtime: 98,
      original_language: "pl"
    },
    %{
      film_id: "7742s2r",
      polish_title: "Eternity. Wybieram ciebie",
      original_title: "Eternity",
      release_year: 2025,
      runtime: 112,
      original_language: "en"
    },
    %{
      film_id: "7622d2r",
      polish_title: "Koszmarek",
      original_title: nil,
      release_year: 2025,
      runtime: 90,
      original_language: nil
    },
    %{
      film_id: "7793s2r",
      polish_title: "Bez przebaczenia",
      original_title: nil,
      release_year: 2024,
      runtime: 105,
      original_language: "en"
    }
  ]

  def run_all_tests do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TmdbMatcher Test on Failed Cinema City Movies")
    IO.puts("Testing #{length(@failed_movies)} failed movies")
    IO.puts(String.duplicate("=", 80) <> "\n")

    results =
      Enum.map(@failed_movies, fn movie ->
        test_movie(movie)
      end)

    # Calculate success rate
    successful = Enum.count(results, fn {status, _} -> status == :matched end)
    total = length(results)
    success_rate = Float.round(successful / total * 100, 1)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("RESULTS SUMMARY")
    IO.puts(String.duplicate("=", 80))
    IO.puts("✅ Matched: #{successful}/#{total} (#{success_rate}%)")
    IO.puts("❌ Not Matched: #{total - successful}/#{total}")

    cond do
      successful == total ->
        IO.puts("\n🎉 SUCCESS! All movies matched using TmdbMatcher!")
      successful > 0 ->
        IO.puts("\n⚠️  Partial success. #{successful} movies matched.")
      true ->
        IO.puts("\n❌ FAILURE! No movies matched.")
    end

    IO.puts(String.duplicate("=", 80) <> "\n")

    results
  end

  defp test_movie(movie) do
    IO.puts("\n#{String.duplicate("-", 80)}")
    IO.puts("Testing: #{movie.polish_title}")
    IO.puts("  Film ID: #{movie.film_id}")
    IO.puts("  Original Title: #{inspect(movie.original_title)}")
    IO.puts("  Year: #{movie.release_year}, Runtime: #{movie.runtime} min")
    IO.puts("  Original Language: #{inspect(movie.original_language)}")
    IO.puts(String.duplicate("-", 80))

    # Build movie_data in format expected by TmdbMatcher
    movie_data = %{
      polish_title: movie.polish_title,
      original_title: movie.original_title,
      year: movie.release_year,
      runtime: movie.runtime,
      director: nil,
      country: nil
    }

    IO.puts("  Calling TmdbMatcher.match_movie/1...")
    IO.puts("")

    case TmdbMatcher.match_movie(movie_data) do
      {:ok, tmdb_id, confidence, provider} ->
        IO.puts("✅ MATCHED!")
        IO.puts("  TMDB ID: #{tmdb_id}")
        IO.puts("  Confidence: #{Float.round(confidence * 100, 1)}%")
        IO.puts("  Provider: #{provider}")

        # Get movie title for verification
        case TmdbMatcher.find_or_create_movie(tmdb_id) do
          {:ok, matched_movie} ->
            IO.puts("  Movie: #{matched_movie.title}")
            {:matched, %{tmdb_id: tmdb_id, confidence: confidence, title: matched_movie.title, provider: provider}}

          {:error, reason} ->
            IO.puts("  ⚠️  Could not fetch movie details: #{inspect(reason)}")
            {:matched, %{tmdb_id: tmdb_id, confidence: confidence, provider: provider}}
        end

      {:needs_review, _movie_data, candidates} ->
        IO.puts("⚠️  NEEDS REVIEW (Low Confidence)")
        IO.puts("  Candidates found: #{length(candidates)}")
        {:needs_review, %{candidate_count: length(candidates)}}

      {:error, :low_confidence} ->
        IO.puts("❌ FAILED: Low Confidence (<50%)")
        {:failed, :low_confidence}

      {:error, :no_results} ->
        IO.puts("❌ FAILED: No Results from TMDB")
        {:failed, :no_results}

      {:error, :missing_title} ->
        IO.puts("❌ FAILED: Missing Title")
        {:failed, :missing_title}

      {:error, reason} ->
        IO.puts("❌ FAILED: #{inspect(reason)}")
        {:failed, reason}
    end
  end
end

# Run the tests
TmdbMatcherTest.run_all_tests()
