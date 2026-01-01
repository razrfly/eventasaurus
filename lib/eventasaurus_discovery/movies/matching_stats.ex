defmodule EventasaurusDiscovery.Movies.MatchingStats do
  @moduledoc """
  Provides statistics and analytics for the movie matching system.

  This module aggregates data from:
  - MovieDetailJob executions (Cinema City scraper)
  - Movie records with provider metadata
  - Oban job states and outcomes

  Used by the Movie Database Dashboard for observability.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie

  @doc """
  Get overall matching statistics for the given time period.

  Returns a map with:
  - total_lookups: Total movie lookup attempts
  - successful_matches: Successfully matched to TMDB
  - failed_matches: Failed to find a match
  - needs_review: Low confidence matches needing review
  - success_rate: Percentage of successful matches
  """
  def get_overview_stats(hours \\ 24) do
    since = hours_ago(hours)

    # Single query with CASE/WHEN aggregation for all job stats (was 3 separate queries)
    job_stats =
      from(j in "oban_jobs",
        where: j.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
        where: j.inserted_at >= ^since,
        select: %{
          total: count(),
          completed:
            fragment("COUNT(CASE WHEN ? = 'completed' THEN 1 END)", j.state),
          discarded:
            fragment("COUNT(CASE WHEN ? = 'discarded' THEN 1 END)", j.state)
        }
      )
      |> Repo.replica().one() || %{total: 0, completed: 0, discarded: 0}

    total = job_stats.total || 0
    completed = job_stats.completed || 0
    discarded = job_stats.discarded || 0

    # Movies created in the time period (separate table, still 1 query)
    movies_created =
      from(m in Movie,
        where: m.inserted_at >= ^since,
        select: count()
      )
      |> Repo.replica().one() || 0

    success_rate =
      if total > 0 do
        Float.round(completed / total * 100, 1)
      else
        0.0
      end

    %{
      total_lookups: total,
      successful_matches: completed,
      failed_matches: discarded,
      movies_created: movies_created,
      success_rate: success_rate,
      pending: total - completed - discarded
    }
  end

  @doc """
  Get provider breakdown statistics.

  Shows success rates by provider (TMDB, OMDb, IMDB).
  Note: Currently we primarily track TMDB success, but this is
  extensible for multi-provider tracking.

  Accepts pre-computed overview_stats to avoid duplicate queries.
  """
  def get_provider_stats(hours \\ 24, overview_stats \\ nil)

  def get_provider_stats(hours, nil) do
    # Called without pre-computed stats - compute inline (still avoids separate function call)
    get_provider_stats(hours, get_overview_stats(hours))
  end

  def get_provider_stats(_hours, stats) when is_map(stats) do
    # Use pre-computed stats - no duplicate queries
    [
      %{
        provider: :tmdb,
        name: "TMDB",
        lookups: stats.successful_matches + stats.failed_matches,
        successes: stats.successful_matches,
        failures: stats.failed_matches,
        success_rate: stats.success_rate,
        color: "#01B4E4"
      },
      %{
        provider: :omdb,
        name: "OMDb",
        lookups: 0,
        successes: 0,
        failures: 0,
        success_rate: 0.0,
        color: "#F5C518"
      },
      %{
        provider: :imdb,
        name: "IMDB",
        lookups: 0,
        successes: 0,
        failures: 0,
        success_rate: 0.0,
        color: "#DBA506"
      }
    ]
  end

  @doc """
  Get confidence distribution of matched movies.

  Returns counts by confidence buckets for visualization.
  Buckets: ≥95%, 85-94%, 70-84%, 50-69%, <50%
  """
  def get_confidence_distribution(hours \\ 168) do
    since = hours_ago(hours)

    # Query movies created in time period
    # Confidence is stored in metadata if available
    movies =
      from(m in Movie,
        where: m.inserted_at >= ^since,
        select: m.metadata
      )
      |> Repo.replica().all()

    # Group by confidence buckets (5 buckets per Issue #3083 spec)
    # Default to 0.8 (80%) if not explicitly stored
    movies
    |> Enum.map(fn metadata ->
      get_in(metadata || %{}, ["match_confidence"]) || 0.8
    end)
    |> Enum.group_by(fn confidence ->
      cond do
        confidence >= 0.95 -> "≥95%"
        confidence >= 0.85 -> "85-94%"
        confidence >= 0.70 -> "70-84%"
        confidence >= 0.50 -> "50-69%"
        true -> "<50%"
      end
    end)
    |> Enum.map(fn {bucket, items} -> {bucket, length(items)} end)
    |> Enum.into(%{})
  end

  @doc """
  Get failure analysis with 7-day trend comparison.

  Returns error breakdown by category with today vs 7-day average comparison.
  Categories: movie_not_ready, duplicate_movie_error, no_results, low_confidence,
              changeset_error, api_timeout, unknown
  """
  def get_failure_analysis(hours \\ 24) do
    now = DateTime.utc_now()
    today_start = hours_ago(hours)
    # 7 days
    week_start = hours_ago(168)

    # Get today's failures by error category
    today_failures = get_failures_by_category(today_start, now)

    # Get 7-day failures for average calculation
    week_failures = get_failures_by_category(week_start, now)

    # Calculate averages (7-day total / 7)
    categories = [
      "movie_not_ready",
      "duplicate_movie_error",
      "no_results",
      "low_confidence",
      "changeset_error",
      "api_timeout",
      "unknown"
    ]

    Enum.map(categories, fn category ->
      today_count = Map.get(today_failures, category, 0)
      week_count = Map.get(week_failures, category, 0)
      week_avg = Float.round(week_count / 7, 1)

      # Calculate trend: compare today to 7-day average
      {trend, trend_pct} = calculate_trend(today_count, week_avg)

      %{
        category: category,
        label: format_category_label(category),
        today: today_count,
        week_avg: week_avg,
        trend: trend,
        trend_pct: trend_pct,
        color: category_color(category)
      }
    end)
    |> Enum.sort_by(& &1.today, :desc)
  end

  defp get_failures_by_category(from_time, to_time) do
    from(j in "oban_jobs",
      where: j.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
      where: j.state == "discarded",
      where: j.discarded_at >= ^from_time and j.discarded_at <= ^to_time,
      select: j.errors
    )
    |> Repo.replica().all()
    |> Enum.map(&categorize_error/1)
    |> Enum.frequencies()
  end

  defp categorize_error(errors) when is_list(errors) do
    # Get the last error message from Oban's error array
    case errors do
      [%{"error" => error} | _] -> categorize_error_message(error)
      [%{"message" => msg} | _] -> categorize_error_message(msg)
      _ -> "unknown"
    end
  end

  defp categorize_error(_), do: "unknown"

  defp categorize_error_message(msg) when is_binary(msg) do
    cond do
      String.contains?(msg, "movie_not_ready") or String.contains?(msg, "snooze") ->
        "movie_not_ready"

      String.contains?(msg, "duplicate") or String.contains?(msg, "already exists") ->
        "duplicate_movie_error"

      String.contains?(msg, "no results") or String.contains?(msg, "not found") or
        String.contains?(msg, "No movie found") or String.contains?(msg, "tmdb_no_results") ->
        "no_results"

      String.contains?(msg, "needs_review") or String.contains?(msg, "tmdb_needs_review") ->
        "low_confidence"

      String.contains?(msg, "low_confidence") or String.contains?(msg, "tmdb_low_confidence") ->
        "low_confidence"

      String.contains?(msg, "timeout") or String.contains?(msg, "HTTPoison") or
          String.contains?(msg, "connection") ->
        "api_timeout"

      # Ecto changeset validation errors (e.g., "is invalid" from cast failures)
      String.contains?(msg, "is invalid") or String.contains?(msg, "validation: :cast") or
        String.contains?(msg, "changeset") or String.contains?(msg, "Ecto.Changeset") ->
        "changeset_error"

      true ->
        "unknown"
    end
  end

  defp categorize_error_message(_), do: "unknown"

  defp calculate_trend(today, avg) when avg == 0 and today == 0, do: {:stable, 0.0}
  defp calculate_trend(_today, avg) when avg == 0, do: {:up, 100.0}

  defp calculate_trend(today, avg) do
    diff_pct = Float.round((today - avg) / avg * 100, 1)

    cond do
      diff_pct > 20 -> {:up, diff_pct}
      diff_pct < -20 -> {:down, abs(diff_pct)}
      true -> {:stable, abs(diff_pct)}
    end
  end

  defp format_category_label("movie_not_ready"), do: "Movie Not Ready"
  defp format_category_label("duplicate_movie_error"), do: "Duplicate Error"
  defp format_category_label("no_results"), do: "No Results"
  defp format_category_label("low_confidence"), do: "Low Confidence"
  defp format_category_label("changeset_error"), do: "Changeset Error"
  defp format_category_label("api_timeout"), do: "API Timeout"
  defp format_category_label("unknown"), do: "Unknown"
  defp format_category_label(other), do: Phoenix.Naming.humanize(other)

  defp category_color("movie_not_ready"), do: "#f59e0b"
  defp category_color("duplicate_movie_error"), do: "#ef4444"
  defp category_color("no_results"), do: "#8b5cf6"
  defp category_color("low_confidence"), do: "#ec4899"
  defp category_color("changeset_error"), do: "#f97316"
  defp category_color("api_timeout"), do: "#3b82f6"
  defp category_color("unknown"), do: "#6b7280"
  defp category_color(_), do: "#6b7280"

  @doc """
  Get recent match failures for analysis.

  Returns the most recent failed movie lookups with error details.
  """
  def get_recent_failures(limit \\ 20) do
    from(j in "oban_jobs",
      where: j.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
      where: j.state == "discarded",
      order_by: [desc: j.discarded_at],
      limit: ^limit,
      select: %{
        id: j.id,
        args: j.args,
        errors: j.errors,
        discarded_at: j.discarded_at,
        attempt: j.attempt
      }
    )
    |> Repo.replica().all()
    |> Enum.map(&format_failure/1)
  end

  @doc """
  Get movies needing review (low confidence matches).

  These are movies that were matched but with lower confidence,
  and may need manual verification.
  """
  def get_movies_needing_review(limit \\ 20) do
    # Movies with low confidence or missing data
    from(m in Movie,
      where: is_nil(m.poster_url) or is_nil(m.runtime),
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      select: %{
        id: m.id,
        title: m.title,
        tmdb_id: m.tmdb_id,
        poster_url: m.poster_url,
        runtime: m.runtime,
        metadata: m.metadata,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.replica().all()
    |> Enum.map(fn movie ->
      # Default to 0.8 for consistency with get_recent_matches
      # Movies without explicit match_confidence are assumed to be high-confidence TMDB matches
      confidence = get_in(movie.metadata || %{}, ["match_confidence"]) || 0.8

      issues =
        []
        |> maybe_add_issue(is_nil(movie.poster_url), "Missing poster")
        |> maybe_add_issue(is_nil(movie.runtime), "Missing runtime")
        |> maybe_add_issue(confidence < 0.7, "Low confidence (#{trunc(confidence * 100)}%)")

      Map.put(movie, :issues, issues)
    end)
  end

  @doc """
  Get recent successful matches (activity feed).
  """
  def get_recent_matches(limit \\ 10) do
    from(m in Movie,
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      select: %{
        id: m.id,
        title: m.title,
        tmdb_id: m.tmdb_id,
        original_title: m.original_title,
        poster_url: m.poster_url,
        runtime: m.runtime,
        metadata: m.metadata,
        inserted_at: m.inserted_at
      }
    )
    |> Repo.replica().all()
    |> Enum.map(fn movie ->
      metadata = movie.metadata || %{}
      source_title = get_in(metadata, ["cinema_city_polish_title"])
      confidence = get_in(metadata, ["match_confidence"]) || 0.8
      provider = get_in(metadata, ["matched_by_provider"]) || "tmdb"

      # Extract cinema_city_film_ids (array format) or fallback to legacy singular format
      cinema_city_film_ids = get_in(metadata, ["cinema_city_film_ids"])
      cinema_city_film_id = get_in(metadata, ["cinema_city_film_id"])

      movie
      |> Map.put(:source_title, source_title)
      |> Map.put(:confidence, confidence)
      |> Map.put(:provider, provider)
      |> Map.put(:cinema_city_film_ids, cinema_city_film_ids)
      |> Map.put(:cinema_city_film_id, cinema_city_film_id)
    end)
  end

  @doc """
  Get hourly match counts for sparkline visualization.
  """
  def get_hourly_counts(hours \\ 24) do
    since = hours_ago(hours)

    # Get hourly counts from Movie table
    from(m in Movie,
      where: m.inserted_at >= ^since,
      group_by: fragment("date_trunc('hour', ?)", m.inserted_at),
      order_by: fragment("date_trunc('hour', ?)", m.inserted_at),
      select: %{
        hour: fragment("date_trunc('hour', ?)", m.inserted_at),
        count: count()
      }
    )
    |> Repo.replica().all()
    |> fill_missing_hours(hours)
  end

  @doc """
  Get unmatched movies blocking showtimes from ShowtimeProcessJob failures.

  This queries ShowtimeProcessJob jobs that failed due to movie_not_matched,
  grouping by movie title to show which movies are blocking the most showtimes.

  Returns a list of maps with:
  - polish_title: The Polish title of the movie
  - original_title: The original title (if available)
  - blocked_count: Number of showtimes blocked
  - first_seen: When this movie first failed
  - last_seen: Most recent failure
  """
  def get_unmatched_movies_blocking_showtimes(hours \\ 168) do
    since = hours_ago(hours)

    # Query ShowtimeProcessJob failures (cancelled or discarded)
    # These are showtimes that couldn't be created because the movie wasn't matched
    from(j in "oban_jobs",
      where: j.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob",
      where: j.state in ["cancelled", "discarded"],
      where: j.inserted_at >= ^since,
      select: %{
        args: j.args,
        inserted_at: j.inserted_at
      }
    )
    |> Repo.replica().all()
    |> Enum.reduce(%{}, fn job, acc ->
      # Extract movie info from job args
      # Args structure: %{"showtime" => %{"film" => %{"polish_title" => "...", ...}}}
      showtime = job.args["showtime"] || %{}
      film = showtime["film"] || %{}
      polish_title = film["polish_title"] || film["title"] || "Unknown"
      original_title = film["original_title"]

      key = {polish_title, original_title}

      Map.update(
        acc,
        key,
        %{count: 1, first: job.inserted_at, last: job.inserted_at},
        fn existing ->
          %{
            count: existing.count + 1,
            first: min_datetime(existing.first, job.inserted_at),
            last: max_datetime(existing.last, job.inserted_at)
          }
        end
      )
    end)
    |> Enum.map(fn {{polish_title, original_title}, data} ->
      %{
        polish_title: polish_title,
        original_title: original_title,
        blocked_count: data.count,
        first_seen: data.first,
        last_seen: data.last
      }
    end)
    |> Enum.sort_by(& &1.blocked_count, :desc)
  end

  @doc """
  Get aggregate impact metrics for unmatched movies.

  Returns:
  - total_blocked_showtimes: Total number of showtimes blocked
  - unique_unmatched_movies: Number of unique movies that aren't matched
  - showtime_loss_rate: Percentage of showtimes blocked vs total attempted

  Accepts pre-computed unmatched_movies list to avoid duplicate queries.
  """
  def get_showtime_impact_metrics(hours \\ 168, unmatched_movies \\ nil)

  def get_showtime_impact_metrics(hours, nil) do
    # Called without pre-computed data - compute inline
    get_showtime_impact_metrics(hours, get_unmatched_movies_blocking_showtimes(hours))
  end

  def get_showtime_impact_metrics(hours, unmatched_movies) when is_list(unmatched_movies) do
    since = hours_ago(hours)

    # Total ShowtimeProcessJob attempts
    total_attempted =
      from(j in "oban_jobs",
        where: j.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob",
        where: j.inserted_at >= ^since,
        select: count()
      )
      |> Repo.replica().one() || 0

    # Failed ShowtimeProcessJobs (blocked)
    blocked =
      from(j in "oban_jobs",
        where: j.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob",
        where: j.state in ["cancelled", "discarded"],
        where: j.inserted_at >= ^since,
        select: count()
      )
      |> Repo.replica().one() || 0

    loss_rate =
      if total_attempted > 0 do
        Float.round(blocked / total_attempted * 100, 1)
      else
        0.0
      end

    %{
      total_blocked_showtimes: blocked,
      unique_unmatched_movies: length(unmatched_movies),
      total_showtime_attempts: total_attempted,
      showtime_loss_rate: loss_rate
    }
  end

  # Helper for datetime comparison
  defp min_datetime(a, b) do
    case NaiveDateTime.compare(a, b) do
      :lt -> a
      _ -> b
    end
  end

  defp max_datetime(a, b) do
    case NaiveDateTime.compare(a, b) do
      :gt -> a
      _ -> b
    end
  end

  @doc """
  Get duplicate cinema_city_film_id count for data quality monitoring.

  Checks both legacy singular format (cinema_city_film_id) and new array format
  (cinema_city_film_ids) for duplicates.

  Note: With the new array format, duplicates are less likely since multiple
  film_ids can be stored on the same movie. This function mainly tracks
  legacy duplicates that may still exist.
  """
  def get_duplicate_film_id_count do
    # Check legacy singular format for duplicates
    legacy_duplicates =
      from(m in Movie,
        where: fragment("?->>'cinema_city_film_id' IS NOT NULL", m.metadata),
        group_by: fragment("?->>'cinema_city_film_id'", m.metadata),
        having: count() > 1,
        select: count()
      )
      |> Repo.replica().all()
      |> length()

    # For array format, duplicates would mean the same film_id appears in
    # multiple movies' arrays - this is a more complex query but less likely
    # to occur with the new design
    legacy_duplicates
  end

  @doc """
  Get total movie count in database.
  """
  def get_total_movie_count do
    from(m in Movie, select: count())
    |> Repo.replica().one() || 0
  end

  @doc """
  Get movies with Cinema City film IDs.

  Counts movies that have either:
  - New array format: cinema_city_film_ids (array)
  - Legacy singular format: cinema_city_film_id (string)
  """
  def get_cinema_city_movie_count do
    from(m in Movie,
      where:
        fragment("?->'cinema_city_film_ids' IS NOT NULL", m.metadata) or
          fragment("?->>'cinema_city_film_id' IS NOT NULL", m.metadata),
      select: count()
    )
    |> Repo.replica().one() || 0
  end

  @doc """
  Confirm a movie match as correct (mark as reviewed).

  Updates the movie's metadata to indicate it has been manually reviewed.
  """
  def confirm_movie_match(movie_id) do
    case Repo.get(Movie, movie_id) do
      nil ->
        {:error, :not_found}

      movie ->
        updated_metadata =
          (movie.metadata || %{})
          |> Map.put("reviewed", true)
          |> Map.put("reviewed_at", DateTime.utc_now() |> DateTime.to_iso8601())
          |> Map.put("match_confidence", 1.0)

        movie
        |> Ecto.Changeset.change(metadata: updated_metadata)
        |> Repo.update()
    end
  end

  @doc """
  Reject a movie match (remove cinema_city_film_ids for re-matching).

  This clears all Cinema City film IDs from metadata so the next scraper run
  will attempt to re-match this movie with potentially better data.

  Handles both:
  - New array format: cinema_city_film_ids (array)
  - Legacy singular format: cinema_city_film_id (string)
  """
  def reject_movie_match(movie_id) do
    case Repo.get(Movie, movie_id) do
      nil ->
        {:error, :not_found}

      movie ->
        updated_metadata =
          (movie.metadata || %{})
          # Remove both legacy and new format
          |> Map.delete("cinema_city_film_id")
          |> Map.delete("cinema_city_film_ids")
          |> Map.put("rejected_at", DateTime.utc_now() |> DateTime.to_iso8601())
          |> Map.put("needs_rematch", true)

        movie
        |> Ecto.Changeset.change(metadata: updated_metadata)
        |> Repo.update()
    end
  end

  # Private helpers

  defp hours_ago(hours) do
    DateTime.utc_now()
    |> DateTime.add(-hours * 3600, :second)
  end

  defp format_failure(%{args: args, errors: errors} = job) do
    film_data = args["film_data"] || %{}
    polish_title = film_data["polish_title"] || args["polish_title"] || "Unknown"
    original_title = film_data["original_title"] || args["original_title"]
    cinema_city_film_id = args["cinema_city_film_id"]

    # Parse error from Oban errors array
    last_error =
      case errors do
        [%{"error" => error} | _] -> error
        [%{"message" => msg} | _] -> msg
        _ -> "Unknown error"
      end

    %{
      id: job.id,
      polish_title: polish_title,
      original_title: original_title,
      cinema_city_film_id: cinema_city_film_id,
      error: last_error,
      discarded_at: job.discarded_at,
      attempts: job.attempt
    }
  end

  defp maybe_add_issue(issues, true, issue), do: [issue | issues]
  defp maybe_add_issue(issues, false, _issue), do: issues

  defp fill_missing_hours(counts, hours) do
    now = DateTime.utc_now()

    # Create a map of hour -> count
    count_map =
      counts
      |> Enum.map(fn %{hour: hour, count: count} ->
        # Truncate to hour for comparison
        truncated =
          hour
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.truncate(:second)

        {truncated, count}
      end)
      |> Enum.into(%{})

    # Generate all hours in the period
    0..(hours - 1)
    |> Enum.map(fn h ->
      hour =
        now
        |> DateTime.add(-h * 3600, :second)
        |> DateTime.truncate(:second)
        |> then(fn dt ->
          %{dt | minute: 0, second: 0}
        end)

      count = Map.get(count_map, hour, 0)
      %{hour: hour, count: count}
    end)
    |> Enum.reverse()
  end
end
