defmodule Mix.Tasks.Benchmark.MovieLookup do
  @moduledoc """
  Benchmark movie lookup performance across providers.

  Tests the MovieLookupService with a set of known Polish titles,
  measuring success rate, provider usage, and timing.

  ## Usage

      # Run full benchmark
      mix benchmark.movie_lookup

      # Run with specific providers only (for A/B testing)
      mix benchmark.movie_lookup --providers tmdb,omdb
      mix benchmark.movie_lookup --providers tmdb,omdb,imdb

      # Skip cache for fresh results
      mix benchmark.movie_lookup --skip-cache

      # Verbose output
      mix benchmark.movie_lookup --verbose
  """

  use Mix.Task

  alias EventasaurusDiscovery.Movies.MovieLookupService
  alias EventasaurusDiscovery.Movies.Providers.{TmdbProvider, OmdbProvider, ImdbProvider}

  @shortdoc "Benchmark movie lookup performance"

  # Test cases from the audit - mix of expected successes and failures
  @test_cases [
    # Previously successful matches (should still work)
    %{polish_title: "Gladiator 2", year: 2024, expected: :success},
    %{polish_title: "Vaiana 2", year: 2024, expected: :success},
    %{polish_title: "Wicked", year: 2024, expected: :success},

    # Classic films - IMDB should help via AKA data
    %{polish_title: "Siedmiu samurajów", year: 1954, expected: :imdb_helps, expected_tmdb: 346},
    %{polish_title: "To wspaniałe życie", year: 1946, expected: :imdb_helps, expected_tmdb: 1585},

    # Ambiguous titles - need review
    %{polish_title: "Dziki", year: 2020, expected: :needs_review},

    # Obscure Polish content - likely to fail
    %{polish_title: "Bing: Święta i inne opowieści", year: 2020, expected: :no_results},
    %{polish_title: "Błekitny szlak", year: nil, expected: :no_results},

    # Additional test cases
    %{polish_title: "Święta z Astrid Lindgren", year: 2023, expected: :needs_review},
    %{polish_title: "2000 metrów do Andrijiwki", year: nil, expected: :needs_review},
    %{polish_title: "Rok z życia kraju", year: nil, expected: :needs_review},
    %{polish_title: "Piernikowe serce", year: nil, expected: :needs_review},
    %{polish_title: "Ścieżki życia", year: nil, expected: :needs_review}
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          providers: :string,
          skip_cache: :boolean,
          verbose: :boolean
        ]
      )

    # Start the application
    Mix.Task.run("app.start")

    # Initialize cache
    MovieLookupService.init_cache()

    # Parse provider option
    providers = parse_providers(opts[:providers])
    skip_cache = opts[:skip_cache] || false
    verbose = opts[:verbose] || false

    IO.puts("")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("  MOVIE LOOKUP BENCHMARK")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")
    IO.puts("Configuration:")
    IO.puts("  Providers: #{format_providers(providers)}")
    IO.puts("  Skip Cache: #{skip_cache}")
    IO.puts("  Test Cases: #{length(@test_cases)}")
    IO.puts("")

    # Check provider availability
    IO.puts("Provider Status:")
    IO.puts("  TmdbProvider: ✅ Available")
    IO.puts("  OmdbProvider: ✅ Available")

    imdb_status =
      if ImdbProvider in providers and EventasaurusDiscovery.Movies.ImdbService.available?() do
        "✅ Available (Zyte configured)"
      else
        "⚠️  Skipped (Zyte not configured or excluded)"
      end

    IO.puts("  ImdbProvider: #{imdb_status}")
    IO.puts("")

    # Run benchmark
    IO.puts("-" |> String.duplicate(70))
    IO.puts("Running Benchmark...")
    IO.puts("-" |> String.duplicate(70))
    IO.puts("")

    start_time = System.monotonic_time(:millisecond)

    results =
      Enum.map(@test_cases, fn test_case ->
        run_test_case(test_case, providers, skip_cache, verbose)
      end)

    total_time = System.monotonic_time(:millisecond) - start_time

    # Analyze results
    analyze_results(results, total_time, providers)
  end

  defp parse_providers(nil), do: [TmdbProvider, OmdbProvider, ImdbProvider]

  defp parse_providers(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn
      "tmdb" -> TmdbProvider
      "omdb" -> OmdbProvider
      "imdb" -> ImdbProvider
      other -> raise "Unknown provider: #{other}"
    end)
  end

  defp format_providers(providers) do
    providers
    |> Enum.map(fn
      TmdbProvider -> "TMDB"
      OmdbProvider -> "OMDb"
      ImdbProvider -> "IMDB"
    end)
    |> Enum.join(", ")
  end

  defp run_test_case(test_case, providers, skip_cache, verbose) do
    title = test_case.polish_title
    year = test_case.year

    if verbose do
      IO.puts("Testing: \"#{title}\"#{if year, do: " (#{year})", else: ""}...")
    end

    query = %{polish_title: title}
    query = if year, do: Map.put(query, :year, year), else: query

    opts = [
      providers: providers,
      skip_cache: skip_cache
    ]

    start_time = System.monotonic_time(:millisecond)
    result = MovieLookupService.lookup(query, opts)
    duration = System.monotonic_time(:millisecond) - start_time

    outcome =
      case result do
        {:ok, tmdb_id, confidence, provider, extra} ->
          %{
            status: :success,
            tmdb_id: tmdb_id,
            confidence: confidence,
            provider: provider,
            imdb_id: extra[:imdb_id],
            duration: duration
          }

        {:needs_review, candidates} ->
          %{
            status: :needs_review,
            candidates: length(candidates),
            top_confidence: get_top_confidence(candidates),
            duration: duration
          }

        {:error, :no_results} ->
          %{status: :no_results, duration: duration}

        {:error, :low_confidence} ->
          %{status: :low_confidence, duration: duration}

        {:error, reason} ->
          %{status: :error, reason: reason, duration: duration}
      end

    if verbose do
      print_verbose_result(title, outcome)
    end

    Map.merge(test_case, %{outcome: outcome})
  end

  defp get_top_confidence([]), do: 0.0

  defp get_top_confidence(candidates) do
    candidates
    |> Enum.map(&(&1[:confidence] || 0.0))
    |> Enum.max()
  end

  defp print_verbose_result(title, outcome) do
    status_icon =
      case outcome.status do
        :success -> "✅"
        :needs_review -> "🔍"
        :no_results -> "❌"
        :low_confidence -> "⚠️"
        :error -> "💥"
      end

    details =
      case outcome.status do
        :success ->
          imdb_suffix = if outcome.imdb_id, do: ", IMDB: #{outcome.imdb_id}", else: ""

          "TMDB #{outcome.tmdb_id} (#{trunc(outcome.confidence * 100)}% via #{outcome.provider}#{imdb_suffix})"

        :needs_review ->
          "#{outcome.candidates} candidates (top: #{trunc(outcome.top_confidence * 100)}%)"

        :no_results ->
          "No results"

        :low_confidence ->
          "Low confidence"

        :error ->
          "Error: #{inspect(outcome.reason)}"
      end

    IO.puts("  #{status_icon} #{title}: #{details} [#{outcome.duration}ms]")
  end

  defp analyze_results(results, total_time, providers) do
    IO.puts("")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("  BENCHMARK RESULTS")
    IO.puts("=" |> String.duplicate(70))
    IO.puts("")

    # Group by outcome status
    by_status = Enum.group_by(results, & &1.outcome.status)

    success_count = length(by_status[:success] || [])
    needs_review_count = length(by_status[:needs_review] || [])
    no_results_count = length(by_status[:no_results] || [])
    low_confidence_count = length(by_status[:low_confidence] || [])
    error_count = length(by_status[:error] || [])
    total = length(results)

    success_rate = Float.round(success_count / total * 100, 1)
    match_rate = Float.round((success_count + needs_review_count) / total * 100, 1)

    IO.puts("Summary:")
    IO.puts("  Total Test Cases: #{total}")
    IO.puts("  ✅ Success (high confidence): #{success_count} (#{success_rate}%)")
    IO.puts("  🔍 Needs Review: #{needs_review_count}")
    IO.puts("  ❌ No Results: #{no_results_count}")
    IO.puts("  ⚠️  Low Confidence: #{low_confidence_count}")
    IO.puts("  💥 Errors: #{error_count}")
    IO.puts("")
    IO.puts("  Success Rate: #{success_rate}%")
    IO.puts("  Match Rate (success + review): #{match_rate}%")
    IO.puts("")

    # Timing analysis
    durations = Enum.map(results, & &1.outcome.duration)
    avg_duration = Float.round(Enum.sum(durations) / length(durations), 1)
    max_duration = Enum.max(durations)
    min_duration = Enum.min(durations)

    IO.puts("Timing:")
    IO.puts("  Total Time: #{total_time}ms")
    IO.puts("  Avg per Lookup: #{avg_duration}ms")
    IO.puts("  Min: #{min_duration}ms, Max: #{max_duration}ms")
    IO.puts("")

    # Check IMDB-expected cases
    imdb_cases = Enum.filter(results, &(&1.expected == :imdb_helps))

    if length(imdb_cases) > 0 do
      IO.puts("IMDB-Expected Cases (classic films):")

      Enum.each(imdb_cases, fn result ->
        status_icon = if result.outcome.status == :success, do: "✅", else: "❌"

        details =
          case result.outcome.status do
            :success ->
              correct =
                if result[:expected_tmdb] == result.outcome.tmdb_id, do: "correct", else: "WRONG"

              "TMDB #{result.outcome.tmdb_id} (#{correct})"

            :needs_review ->
              "#{result.outcome.candidates} candidates"

            _ ->
              "#{result.outcome.status}"
          end

        IO.puts("  #{status_icon} #{result.polish_title}: #{details}")
      end)

      IO.puts("")
    end

    # Detailed failure analysis
    failures =
      Enum.filter(results, fn r ->
        r.outcome.status in [:no_results, :error, :low_confidence]
      end)

    if length(failures) > 0 do
      IO.puts("Failed Lookups:")

      Enum.each(failures, fn result ->
        IO.puts("  ❌ #{result.polish_title}")
      end)

      IO.puts("")
    end

    # Print providers used
    IO.puts("-" |> String.duplicate(70))
    IO.puts("Providers: #{format_providers(providers)}")
    IO.puts("Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}")
    IO.puts("-" |> String.duplicate(70))
    IO.puts("")

    # Return summary for programmatic use
    %{
      total: total,
      success: success_count,
      needs_review: needs_review_count,
      no_results: no_results_count,
      success_rate: success_rate,
      match_rate: match_rate,
      avg_duration: avg_duration,
      total_time: total_time,
      providers: providers
    }
  end
end
