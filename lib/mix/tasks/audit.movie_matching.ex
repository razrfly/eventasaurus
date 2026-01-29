defmodule Mix.Tasks.Audit.MovieMatching do
  @moduledoc """
  Audit movie matching success rates and identify failed matches.

  Shows comprehensive statistics about movie matching from Cinema City
  and other sources, including:
  - Overall matching success rate
  - Failed movies with reasons
  - Cancelled showtimes grouped by movie
  - Provider configuration status
  - Recommendations for improvement

  ## Usage

      # Show current matching stats
      mix audit.movie_matching

      # Show more detail about failures
      mix audit.movie_matching --verbose

      # Check specific hours (default: 24)
      mix audit.movie_matching --hours 48

      # Retry failed matches (dry run)
      mix audit.movie_matching --retry

      # Actually retry failed matches
      mix audit.movie_matching --retry --apply

  ## Output

  - Matching statistics (completed, cancelled, discarded)
  - Failed movies with film_ids and titles
  - Impact (cancelled showtimes per movie)
  - Provider configuration status
  - Actionable recommendations
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo

  @shortdoc "Audit movie matching success rates"

  @impl Mix.Task
  @spec run([binary()]) :: :ok
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [hours: :integer, verbose: :boolean, retry: :boolean, apply: :boolean],
        aliases: [h: :hours, v: :verbose, r: :retry, a: :apply]
      )

    hours = opts[:hours] || 24
    verbose = opts[:verbose] || false
    retry = opts[:retry] || false
    apply_retry = opts[:apply] || false

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "🎬 Movie Matching Audit Report" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 70) <> IO.ANSI.reset())
    IO.puts("Period: Last #{hours} hours")
    IO.puts("")

    # Get stats from Oban jobs
    stats = get_matching_stats(hours)
    display_matching_stats(stats)

    # Get failed movies
    failed_movies = get_failed_movies(hours)
    display_failed_movies(failed_movies, verbose)

    # Get cancelled showtimes grouped by movie
    cancelled_showtimes = get_cancelled_showtimes(hours)
    display_cancelled_showtimes(cancelled_showtimes)

    # Check provider configuration
    display_provider_status()

    # Calculate matching rate
    total = stats.completed + stats.discarded + stats.cancelled
    match_rate = if total > 0, do: Float.round(stats.completed / total * 100, 1), else: 0.0

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 70) <> IO.ANSI.reset())

    # Target status
    target = 95.0
    gap = target - match_rate

    if match_rate >= target do
      IO.puts(
        IO.ANSI.green() <>
          "✅ Target achieved! Match rate: #{match_rate}% (target: #{target}%)" <> IO.ANSI.reset()
      )
    else
      IO.puts(
        IO.ANSI.yellow() <>
          "📊 Current match rate: #{match_rate}% (target: #{target}%, gap: #{Float.round(gap, 1)}%)" <>
          IO.ANSI.reset()
      )
    end

    # Recommendations
    display_recommendations(failed_movies, cancelled_showtimes, match_rate)

    # Retry logic
    if retry do
      IO.puts("")
      retry_failed_matches(failed_movies, apply_retry)
    end

    IO.puts("")
  end

  defp get_matching_stats(hours) do
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)

    # Query MovieDetailJob stats
    query = """
    SELECT
      state,
      COUNT(*) as count
    FROM oban_jobs
    WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob'
      AND inserted_at >= $1
    GROUP BY state
    """

    result = Repo.query!(query, [from_time])

    Enum.reduce(
      result.rows,
      %{
        completed: 0,
        discarded: 0,
        cancelled: 0,
        retryable: 0,
        available: 0,
        executing: 0,
        scheduled: 0
      },
      fn [state, count], acc ->
        case state do
          "completed" -> %{acc | completed: count}
          "discarded" -> %{acc | discarded: count}
          "cancelled" -> %{acc | cancelled: count}
          "retryable" -> %{acc | retryable: count}
          "available" -> %{acc | available: count}
          "executing" -> %{acc | executing: count}
          "scheduled" -> %{acc | scheduled: count}
          _ -> acc
        end
      end
    )
  end

  defp display_matching_stats(stats) do
    IO.puts(IO.ANSI.blue() <> "📊 MovieDetailJob Statistics" <> IO.ANSI.reset())
    IO.puts(String.duplicate("─", 70))

    total = stats.completed + stats.discarded + stats.cancelled
    in_progress = stats.available + stats.executing + stats.scheduled + stats.retryable

    IO.puts("  #{IO.ANSI.green()}Completed:#{IO.ANSI.reset()}  #{stats.completed}")
    IO.puts("  #{IO.ANSI.red()}Discarded:#{IO.ANSI.reset()}  #{stats.discarded}")
    IO.puts("  #{IO.ANSI.yellow()}Cancelled:#{IO.ANSI.reset()}  #{stats.cancelled}")

    if in_progress > 0 do
      IO.puts(
        "  In Progress: #{in_progress} (available: #{stats.available}, executing: #{stats.executing}, scheduled: #{stats.scheduled}, retryable: #{stats.retryable})"
      )
    end

    IO.puts("  #{IO.ANSI.cyan()}Total:#{IO.ANSI.reset()}      #{total}")

    if total > 0 do
      success_rate = Float.round(stats.completed / total * 100, 1)
      IO.puts("  Success Rate: #{success_rate}%")
    end

    IO.puts("")
  end

  defp get_failed_movies(hours) do
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)

    query = """
    SELECT
      args->>'cinema_city_film_id' as film_id,
      args->'film_data'->>'polish_title' as polish_title,
      args->'film_data'->>'original_title' as original_title,
      state,
      errors::text as errors
    FROM oban_jobs
    WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob'
      AND state IN ('discarded', 'cancelled')
      AND inserted_at >= $1
    ORDER BY inserted_at DESC
    """

    result = Repo.query!(query, [from_time])

    Enum.map(result.rows, fn [film_id, polish_title, original_title, state, errors] ->
      %{
        film_id: film_id,
        polish_title: polish_title,
        original_title: original_title,
        state: state,
        errors: parse_errors(errors)
      }
    end)
  end

  defp parse_errors(nil), do: nil

  defp parse_errors(errors_str) when is_binary(errors_str) do
    case Jason.decode(errors_str) do
      {:ok, errors} when is_list(errors) ->
        # Get the last error
        case List.last(errors) do
          %{"error" => error} -> extract_error_reason(error)
          _ -> "Unknown"
        end

      _ ->
        "Parse error"
    end
  end

  defp extract_error_reason(error) when is_binary(error) do
    cond do
      String.contains?(error, "no_results") -> "No TMDB results"
      String.contains?(error, "low_confidence") -> "Low confidence match"
      String.contains?(error, "missing_title") -> "Missing title"
      String.contains?(error, "timeout") -> "API timeout"
      true -> String.slice(error, 0, 50)
    end
  end

  defp extract_error_reason(_), do: "Unknown"

  defp display_failed_movies(failed_movies, verbose) do
    if Enum.empty?(failed_movies) do
      IO.puts(IO.ANSI.green() <> "✅ No failed MovieDetailJobs found!" <> IO.ANSI.reset())
      IO.puts("")
    else
      IO.puts(IO.ANSI.red() <> "❌ Failed Movies (#{length(failed_movies)})" <> IO.ANSI.reset())
      IO.puts(String.duplicate("─", 70))

      # Group by film_id to dedupe
      grouped = Enum.group_by(failed_movies, & &1.film_id)

      grouped
      |> Enum.take(if(verbose, do: 50, else: 10))
      |> Enum.each(fn {film_id, movies} ->
        movie = List.first(movies)
        title = movie.polish_title || movie.original_title || "Unknown"
        error = movie.errors || "Unknown"

        IO.puts("  • #{IO.ANSI.yellow()}#{film_id}#{IO.ANSI.reset()}")
        IO.puts("    Title: #{title}")
        IO.puts("    Reason: #{error}")
      end)

      remaining = length(Map.keys(grouped)) - if verbose, do: 50, else: 10

      if remaining > 0 do
        IO.puts("  ... and #{remaining} more (use --verbose to see all)")
      end

      IO.puts("")
    end
  end

  defp get_cancelled_showtimes(hours) do
    from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)

    query = """
    SELECT
      args->'showtime'->'film'->>'cinema_city_film_id' as film_id,
      args->'showtime'->'film'->>'polish_title' as polish_title,
      COUNT(*) as count
    FROM oban_jobs
    WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob'
      AND state = 'cancelled'
      AND inserted_at >= $1
    GROUP BY
      args->'showtime'->'film'->>'cinema_city_film_id',
      args->'showtime'->'film'->>'polish_title'
    ORDER BY count DESC
    """

    result = Repo.query!(query, [from_time])

    Enum.map(result.rows, fn [film_id, polish_title, count] ->
      %{
        film_id: film_id,
        polish_title: polish_title,
        cancelled_count: count
      }
    end)
  end

  defp display_cancelled_showtimes(cancelled) do
    if Enum.empty?(cancelled) do
      IO.puts(IO.ANSI.green() <> "✅ No cancelled showtimes!" <> IO.ANSI.reset())
      IO.puts("")
    else
      total_cancelled = Enum.reduce(cancelled, 0, fn m, acc -> acc + m.cancelled_count end)

      IO.puts(
        IO.ANSI.yellow() <>
          "⚠️  Cancelled Showtimes by Movie (#{total_cancelled} total)" <> IO.ANSI.reset()
      )

      IO.puts(String.duplicate("─", 70))

      Enum.each(cancelled, fn movie ->
        title = movie.polish_title || "Unknown"

        IO.puts(
          "  #{IO.ANSI.red()}#{movie.cancelled_count}#{IO.ANSI.reset()} showtimes - #{title}"
        )

        IO.puts("    Film ID: #{movie.film_id}")

        # Analyze title for common patterns
        patterns = analyze_title_patterns(title)

        if patterns != [] do
          IO.puts("    #{IO.ANSI.cyan()}Patterns: #{Enum.join(patterns, ", ")}#{IO.ANSI.reset()}")
        end
      end)

      IO.puts("")
    end
  end

  defp analyze_title_patterns(title) when is_binary(title) do
    patterns = []

    patterns =
      if String.contains?(String.downcase(title), "ukraiński dubbing") do
        ["Ukrainian dubbing suffix" | patterns]
      else
        patterns
      end

    patterns =
      if String.contains?(String.downcase(title), "dubbing") do
        ["Dubbing variant" | patterns]
      else
        patterns
      end

    patterns =
      if String.contains?(String.downcase(title), "napisy") do
        ["Subtitles variant" | patterns]
      else
        patterns
      end

    patterns =
      if String.match?(title, ~r/\d{4}$/) do
        ["Year suffix" | patterns]
      else
        patterns
      end

    patterns
  end

  defp analyze_title_patterns(_), do: []

  defp display_provider_status do
    IO.puts(IO.ANSI.blue() <> "🔌 Provider Configuration" <> IO.ANSI.reset())
    IO.puts(String.duplicate("─", 70))

    # Check TMDB
    tmdb_key =
      System.get_env("TMDB_API_KEY") || Application.get_env(:eventasaurus_web, :tmdb_api_key)

    tmdb_status = if tmdb_key && tmdb_key != "", do: "✅ Configured", else: "❌ Missing"
    IO.puts("  TMDB:  #{tmdb_status}")

    # Check OMDb
    # NOTE: Uses :eventasaurus namespace (NOT :eventasaurus_discovery)
    discovery_config = Application.get_env(:eventasaurus, :discovery) || []

    omdb_key =
      System.get_env("OMDB_API_KEY") ||
        discovery_config[:omdb_api_key]

    omdb_status =
      if omdb_key && omdb_key != "",
        do: "✅ Configured",
        else: "⚠️  Not configured (fallback disabled)"

    IO.puts("  OMDb:  #{omdb_status}")

    # Check Zyte (for IMDB fallback)
    zyte_key =
      System.get_env("ZYTE_API_KEY") ||
        discovery_config[:zyte_api_key]

    zyte_status =
      if zyte_key && zyte_key != "",
        do: "✅ Configured",
        else: "⚠️  Not configured (IMDB fallback disabled)"

    IO.puts("  Zyte:  #{zyte_status}")

    IO.puts("")

    if is_nil(omdb_key) && is_nil(zyte_key) do
      IO.puts(IO.ANSI.yellow() <> "  ⚠️  No fallback providers configured!" <> IO.ANSI.reset())
      IO.puts("     Only TMDB is available. Consider adding OMDb or Zyte API keys.")
      IO.puts("")
    end
  end

  defp display_recommendations(failed_movies, cancelled_showtimes, match_rate) do
    IO.puts("")
    IO.puts(IO.ANSI.blue() <> "💡 Recommendations" <> IO.ANSI.reset())
    IO.puts(String.duplicate("─", 70))

    recommendations = []

    # Check for Ukrainian dubbing pattern
    ukrainian_movies =
      Enum.filter(cancelled_showtimes, fn m ->
        String.contains?(String.downcase(m.polish_title || ""), "ukraiński dubbing")
      end)

    recommendations =
      if length(ukrainian_movies) > 0 do
        total = Enum.reduce(ukrainian_movies, 0, fn m, acc -> acc + m.cancelled_count end)

        [
          "Add title normalization to strip 'ukraiński dubbing' suffix (#{total} showtimes affected)"
          | recommendations
        ]
      else
        recommendations
      end

    # Check for dubbing variants
    dubbing_movies =
      Enum.filter(cancelled_showtimes, fn m ->
        title = String.downcase(m.polish_title || "")
        String.contains?(title, "dubbing") && !String.contains?(title, "ukraiński")
      end)

    recommendations =
      if length(dubbing_movies) > 0 do
        ["Strip generic 'dubbing' suffix from titles before search" | recommendations]
      else
        recommendations
      end

    # Check match rate
    recommendations =
      if match_rate < 95.0 do
        gap = 95.0 - match_rate
        ["Improve match rate by #{Float.round(gap, 1)}% to reach 95% target" | recommendations]
      else
        recommendations
      end

    # Check provider config
    omdb_key = System.get_env("OMDB_API_KEY")
    zyte_key = System.get_env("ZYTE_API_KEY")

    recommendations =
      if is_nil(omdb_key) do
        ["Configure OMDB_API_KEY for English title fallback" | recommendations]
      else
        recommendations
      end

    recommendations =
      if is_nil(zyte_key) do
        ["Configure ZYTE_API_KEY for IMDB web fallback with Polish AKA data" | recommendations]
      else
        recommendations
      end

    # Check for new/upcoming movies
    recommendations =
      if length(failed_movies) > 0 do
        [
          "Check if failed movies exist in TMDB (may be too new or regional releases)"
          | recommendations
        ]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      IO.puts("  ✅ No immediate actions needed. Match rate is at target!")
    else
      Enum.with_index(recommendations, 1)
      |> Enum.each(fn {rec, i} ->
        IO.puts("  #{i}. #{rec}")
      end)
    end
  end

  defp retry_failed_matches(failed_movies, apply) do
    if Enum.empty?(failed_movies) do
      IO.puts("No failed matches to retry.")
    else
      # Group by film_id to dedupe
      film_ids =
        failed_movies
        |> Enum.map(& &1.film_id)
        |> Enum.uniq()

      if apply do
        IO.puts(
          IO.ANSI.yellow() <> "🔄 Retrying #{length(film_ids)} failed movies..." <> IO.ANSI.reset()
        )

        # Delete old failed jobs and re-insert
        Enum.each(film_ids, fn film_id ->
          # Find the original job to get film_data
          movie = Enum.find(failed_movies, &(&1.film_id == film_id))

          if movie do
            # Delete old failed job
            delete_query = """
            DELETE FROM oban_jobs
            WHERE worker = 'EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob'
              AND args->>'cinema_city_film_id' = $1
              AND state IN ('discarded', 'cancelled')
            """

            Repo.query!(delete_query, [film_id])

            # Re-insert job
            job_args = %{
              "cinema_city_film_id" => film_id,
              "film_data" => %{
                "polish_title" => movie.polish_title,
                "original_title" => movie.original_title
              },
              "source_id" => nil,
              "retry_attempt" => true
            }

            Oban.insert!(
              Oban.Job.new(job_args,
                worker: EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob,
                queue: :scraper_detail
              )
            )

            IO.puts("  ✅ Queued: #{movie.polish_title || film_id}")
          end
        end)

        IO.puts("")

        IO.puts(
          "Done! Jobs queued for retry. Run `mix monitor.jobs list --source cinema_city` to monitor."
        )
      else
        IO.puts(
          IO.ANSI.cyan() <>
            "🔍 Dry run - would retry #{length(film_ids)} movies:" <> IO.ANSI.reset()
        )

        Enum.take(film_ids, 10)
        |> Enum.each(fn film_id ->
          movie = Enum.find(failed_movies, &(&1.film_id == film_id))
          title = (movie && (movie.polish_title || movie.original_title)) || "Unknown"
          IO.puts("  • #{film_id}: #{title}")
        end)

        if length(film_ids) > 10 do
          IO.puts("  ... and #{length(film_ids) - 10} more")
        end

        IO.puts("")
        IO.puts("Run with --apply to actually retry these matches.")
      end
    end
  end
end
