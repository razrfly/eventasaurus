# Comprehensive Cinema City Movie Matching Test
# Tests title extraction + TmdbMatcher on all failed movies
# Run with: mix run test_comprehensive_cinema_city.exs

defmodule ComprehensiveCinemaCityTest do
  @moduledoc """
  Phase 5.4 comprehensive testing on all failed Cinema City movies.

  Tests:
  - Original 7 failed movies (from earlier investigation)
  - 3 currently failed movies (from database query)

  Total: 10 unique movies
  """

  alias EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher

  # Original 7 failed movies from earlier investigation
  @original_failed_movies [
    %{
      film_id: "7441s2r",
      polish_title: "Wicked: Na dobre",
      release_year: 2025,
      runtime: 137,
      original_language: "en",
      source: "original_test"
    },
    %{
      film_id: "7381d2r",
      polish_title: "Zwierzogród 2",
      release_year: 2025,
      runtime: 108,
      original_language: "en",
      source: "original_test"
    },
    %{
      film_id: "7760d2r",
      polish_title: "Psi patrol. Pieski ratują święta",
      release_year: 2025,
      runtime: 68,
      original_language: nil,
      source: "original_test"
    },
    %{
      film_id: "7671o2r",
      polish_title: "Uwierz w Mikołaja 2",
      release_year: 2025,
      runtime: 98,
      original_language: "pl",
      source: "original_test"
    },
    %{
      film_id: "7742s2r",
      polish_title: "Eternity. Wybieram ciebie",
      release_year: 2025,
      runtime: 112,
      original_language: "en",
      source: "original_test"
    },
    %{
      film_id: "7622d2r",
      polish_title: "Koszmarek",
      release_year: 2025,
      runtime: 90,
      original_language: nil,
      source: "original_test"
    },
    %{
      film_id: "7793s2r",
      polish_title: "Bez przebaczenia",
      release_year: 2024,
      runtime: 105,
      original_language: "en",
      source: "original_test"
    }
  ]

  # Currently failed movies from database (last 90 days)
  @current_failed_movies [
    %{
      film_id: "7779d2r",
      polish_title: "Święta z Astrid Lindgren",
      release_year: 2023,
      runtime: 53,
      original_language: nil,
      source: "database_query"
    },
    %{
      film_id: "7739d2r",
      polish_title: "Mysz-masz na Święta",
      release_year: 2025,
      runtime: 80,
      original_language: nil,
      source: "database_query"
    },
    %{
      film_id: "6882d2r",
      polish_title: "Mikołaj i ekipa",
      release_year: 2025,
      runtime: 88,
      original_language: nil,
      source: "database_query"
    }
  ]

  @all_movies @original_failed_movies ++ @current_failed_movies

  def run_all_tests do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Comprehensive Cinema City Movie Matching Test - Phase 5.4")
    IO.puts("Testing #{length(@all_movies)} failed movies (7 original + 3 current)")
    IO.puts(String.duplicate("=", 80) <> "\n")

    results =
      Enum.map(@all_movies, fn movie ->
        test_movie(movie)
      end)

    # Generate comprehensive report
    generate_report(results)

    results
  end

  defp test_movie(movie) do
    IO.puts("\n#{String.duplicate("-", 80)}")
    IO.puts("Testing: #{movie.polish_title}")
    IO.puts("  Film ID: #{movie.film_id}")
    IO.puts("  Year: #{movie.release_year}, Runtime: #{movie.runtime} min")
    IO.puts("  Original Language: #{inspect(movie.original_language)}")
    IO.puts("  Source: #{movie.source}")
    IO.puts(String.duplicate("-", 80))

    # Apply title extraction logic (simulate MovieDetailJob.normalize_film_data/1)
    extracted_title = extract_original_title(movie.polish_title, movie.original_language)

    if extracted_title do
      IO.puts("  ✓ Title extracted: \"#{extracted_title}\"")
    else
      IO.puts("  ℹ  No extraction (Polish-only or no separator)")
    end

    # Build movie_data in format expected by TmdbMatcher
    movie_data = %{
      polish_title: movie.polish_title,
      original_title: extracted_title,
      year: movie.release_year,
      runtime: movie.runtime,
      director: nil,
      country: nil
    }

    IO.puts("  Calling TmdbMatcher.match_movie/1...")
    IO.puts("")

    start_time = System.monotonic_time(:millisecond)

    result = TmdbMatcher.match_movie(movie_data)

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, tmdb_id, confidence, provider} ->
        IO.puts("✅ MATCHED!")
        IO.puts("  TMDB ID: #{tmdb_id}")
        IO.puts("  Confidence: #{Float.round(confidence * 100, 1)}%")
        IO.puts("  Duration: #{duration}ms")
        IO.puts("  Provider: #{provider}")

        # Get movie title for verification
        case TmdbMatcher.find_or_create_movie(tmdb_id) do
          {:ok, matched_movie} ->
            IO.puts("  Movie: #{matched_movie.title}")

            {:matched,
             %{
               film_id: movie.film_id,
               polish_title: movie.polish_title,
               tmdb_id: tmdb_id,
               tmdb_title: matched_movie.title,
               provider: provider,
               confidence: confidence,
               extracted_title: extracted_title,
               duration_ms: duration,
               source: movie.source
             }}

          {:error, reason} ->
            IO.puts("  ⚠️  Could not fetch movie details: #{inspect(reason)}")

            {:matched,
             %{
               film_id: movie.film_id,
               polish_title: movie.polish_title,
               tmdb_id: tmdb_id,
               tmdb_title: "unknown",
               confidence: confidence,
               extracted_title: extracted_title,
               duration_ms: duration,
               source: movie.source
             }}
        end

      {:needs_review, _movie_data, candidates} ->
        IO.puts("⚠️  NEEDS REVIEW (Low Confidence)")
        IO.puts("  Candidates found: #{length(candidates)}")
        IO.puts("  Duration: #{duration}ms")

        {:needs_review,
         %{
           film_id: movie.film_id,
           polish_title: movie.polish_title,
           candidate_count: length(candidates),
           extracted_title: extracted_title,
           duration_ms: duration,
           source: movie.source
         }}

      {:error, :low_confidence} ->
        IO.puts("❌ FAILED: Low Confidence (<50%)")
        IO.puts("  Duration: #{duration}ms")

        {:failed,
         %{
           film_id: movie.film_id,
           polish_title: movie.polish_title,
           reason: :low_confidence,
           extracted_title: extracted_title,
           duration_ms: duration,
           source: movie.source
         }}

      {:error, :no_results} ->
        IO.puts("❌ FAILED: No Results from TMDB")
        IO.puts("  Duration: #{duration}ms")

        {:failed,
         %{
           film_id: movie.film_id,
           polish_title: movie.polish_title,
           reason: :no_results,
           extracted_title: extracted_title,
           duration_ms: duration,
           source: movie.source
         }}

      {:error, :missing_title} ->
        IO.puts("❌ FAILED: Missing Title")
        IO.puts("  Duration: #{duration}ms")

        {:failed,
         %{
           film_id: movie.film_id,
           polish_title: movie.polish_title,
           reason: :missing_title,
           extracted_title: extracted_title,
           duration_ms: duration,
           source: movie.source
         }}

      {:error, reason} ->
        IO.puts("❌ FAILED: #{inspect(reason)}")
        IO.puts("  Duration: #{duration}ms")

        {:failed,
         %{
           film_id: movie.film_id,
           polish_title: movie.polish_title,
           reason: reason,
           extracted_title: extracted_title,
           duration_ms: duration,
           source: movie.source
         }}
    end
  end

  # Extract original English title from mixed-language titles
  # Simulates MovieDetailJob.extract_original_title/2
  defp extract_original_title(polish_title, "en") when is_binary(polish_title) do
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

  defp extract_original_title(_polish_title, _language), do: nil

  defp generate_report(results) do
    # Categorize results
    matched = Enum.filter(results, fn {status, _} -> status == :matched end)
    needs_review = Enum.filter(results, fn {status, _} -> status == :needs_review end)
    failed = Enum.filter(results, fn {status, _} -> status == :failed end)

    # Calculate statistics
    total = length(results)
    matched_count = length(matched)
    needs_review_count = length(needs_review)
    failed_count = length(failed)

    success_rate = if total > 0, do: Float.round(matched_count / total * 100, 1), else: 0.0

    # Calculate average duration
    durations =
      Enum.map(results, fn
        {_, %{duration_ms: ms}} -> ms
        _ -> 0
      end)

    avg_duration = if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0.0

    # Confidence distribution for matched movies
    confidences =
      Enum.map(matched, fn
        {:matched, %{confidence: conf}} -> conf * 100
        _ -> 0
      end)

    excellent_count = Enum.count(confidences, fn c -> c >= 85 end)
    good_count = Enum.count(confidences, fn c -> c >= 75 and c < 85 end)
    acceptable_count = Enum.count(confidences, fn c -> c >= 50 and c < 75 end)

    # Print comprehensive report
    IO.puts("\n\n" <> String.duplicate("=", 80))
    IO.puts("COMPREHENSIVE TEST REPORT - Phase 5.4")
    IO.puts(String.duplicate("=", 80))

    IO.puts("\n📊 OVERALL STATISTICS")
    IO.puts(String.duplicate("-", 80))
    IO.puts("  Total Movies Tested: #{total}")
    IO.puts("  ✅ Matched: #{matched_count} (#{success_rate}%)")
    IO.puts("  ⚠️  Needs Review: #{needs_review_count} (#{Float.round(needs_review_count / total * 100, 1)}%)")
    IO.puts("  ❌ Failed: #{failed_count} (#{Float.round(failed_count / total * 100, 1)}%)")
    IO.puts("  ⏱️  Average Duration: #{Float.round(avg_duration, 1)}ms")

    IO.puts("\n🎯 CONFIDENCE DISTRIBUTION (Matched Movies)")
    IO.puts(String.duplicate("-", 80))
    IO.puts("  ≥85% (Excellent): #{excellent_count}/#{matched_count} (#{if matched_count > 0, do: Float.round(excellent_count / matched_count * 100, 1), else: 0}%)")
    IO.puts("  75-84% (Good): #{good_count}/#{matched_count} (#{if matched_count > 0, do: Float.round(good_count / matched_count * 100, 1), else: 0}%)")
    IO.puts("  50-74% (Acceptable): #{acceptable_count}/#{matched_count} (#{if matched_count > 0, do: Float.round(acceptable_count / matched_count * 100, 1), else: 0}%)")

    IO.puts("\n📋 DETAILED RESULTS")
    IO.puts(String.duplicate("-", 80))

    if matched_count > 0 do
      IO.puts("\n✅ MATCHED MOVIES (#{matched_count}):")

      matched
      |> Enum.sort_by(fn {:matched, %{confidence: c}} -> c end, :desc)
      |> Enum.each(fn {:matched, data} ->
        conf_pct = Float.round(data.confidence * 100, 1)
        extracted = if data.extracted_title, do: " (extracted: \"#{data.extracted_title}\")", else: ""

        IO.puts("  • #{data.polish_title}#{extracted}")
        IO.puts("    → #{data.tmdb_title} (TMDB ID: #{data.tmdb_id})")
        IO.puts("    Confidence: #{conf_pct}% | Duration: #{data.duration_ms}ms | Source: #{data.source}")
      end)
    end

    if needs_review_count > 0 do
      IO.puts("\n⚠️  NEEDS REVIEW (#{needs_review_count}):")

      Enum.each(needs_review, fn {:needs_review, data} ->
        extracted = if data.extracted_title, do: " (extracted: \"#{data.extracted_title}\")", else: ""
        IO.puts("  • #{data.polish_title}#{extracted}")
        IO.puts("    Candidates: #{data.candidate_count} | Duration: #{data.duration_ms}ms | Source: #{data.source}")
      end)
    end

    if failed_count > 0 do
      IO.puts("\n❌ FAILED (#{failed_count}):")

      Enum.each(failed, fn {:failed, data} ->
        extracted = if data.extracted_title, do: " (extracted: \"#{data.extracted_title}\")", else: ""
        IO.puts("  • #{data.polish_title}#{extracted}")
        IO.puts("    Reason: #{data.reason} | Duration: #{data.duration_ms}ms | Source: #{data.source}")
      end)
    end

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("SUCCESS CRITERIA EVALUATION")
    IO.puts(String.duplicate("=", 80))

    criteria = [
      {"Overall Success Rate", success_rate, 90.0, "≥90%"},
      {"High Confidence (≥80%)", if(matched_count > 0, do: (excellent_count + good_count) / matched_count * 100, else: 0), 70.0, "≥70%"},
      {"Needs Review", needs_review_count / total * 100, 25.0, "≤25%"},
      {"Failures", failed_count / total * 100, 10.0, "≤10%"}
    ]

    Enum.each(criteria, fn {name, actual, target, target_str} ->
      status =
        cond do
          name in ["Needs Review", "Failures"] and actual <= target -> "✅ PASS"
          name not in ["Needs Review", "Failures"] and actual >= target -> "✅ PASS"
          true -> "❌ FAIL"
        end

      IO.puts("  #{name}: #{Float.round(actual, 1)}% (Target: #{target_str}) #{status}")
    end)

    IO.puts("\n" <> String.duplicate("=", 80))

    overall_pass =
      success_rate >= 90.0 and
        (if matched_count > 0, do: (excellent_count + good_count) / matched_count * 100 >= 70.0, else: false) and
        needs_review_count / total * 100 <= 25.0 and
        failed_count / total * 100 <= 10.0

    if overall_pass do
      IO.puts("🎉 ALL SUCCESS CRITERIA MET!")
      IO.puts("Recommendation: Proceed with Phase 2 (Code Review)")
    else
      IO.puts("⚠️  SOME SUCCESS CRITERIA NOT MET")
      IO.puts("Recommendation: Review failed cases and adjust thresholds if needed")
    end

    IO.puts(String.duplicate("=", 80) <> "\n")
  end
end

# Run the comprehensive test
ComprehensiveCinemaCityTest.run_all_tests()
