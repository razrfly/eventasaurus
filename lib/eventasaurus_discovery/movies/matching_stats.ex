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

    # Query MovieDetailJob executions from Oban
    base_query =
      from(j in "oban_jobs",
        where: j.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
        where: j.inserted_at >= ^since
      )

    total =
      from(j in base_query, select: count())
      |> Repo.one() || 0

    completed =
      from(j in base_query,
        where: j.state == "completed",
        select: count()
      )
      |> Repo.one() || 0

    discarded =
      from(j in base_query,
        where: j.state == "discarded",
        select: count()
      )
      |> Repo.one() || 0

    # Movies created in the time period (successful matches)
    movies_created =
      from(m in Movie,
        where: m.inserted_at >= ^since,
        select: count()
      )
      |> Repo.one() || 0

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
  """
  def get_provider_stats(hours \\ 24) do
    # For now, all successful matches go through TMDB
    # Future: Parse provider from job metadata when multi-provider is enabled
    stats = get_overview_stats(hours)

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
      |> Repo.all()

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
  Categories: movie_not_ready, duplicate_movie_error, no_results, api_timeout, unknown
  """
  def get_failure_analysis(hours \\ 24) do
    now = DateTime.utc_now()
    today_start = hours_ago(hours)
    week_start = hours_ago(168)  # 7 days

    # Get today's failures by error category
    today_failures = get_failures_by_category(today_start, now)

    # Get 7-day failures for average calculation
    week_failures = get_failures_by_category(week_start, now)

    # Calculate averages (7-day total / 7)
    categories = ["movie_not_ready", "duplicate_movie_error", "no_results", "api_timeout", "unknown"]

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
    |> Repo.all()
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
          String.contains?(msg, "No movie found") ->
        "no_results"

      String.contains?(msg, "timeout") or String.contains?(msg, "HTTPoison") or
          String.contains?(msg, "connection") ->
        "api_timeout"

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
  defp format_category_label("api_timeout"), do: "API Timeout"
  defp format_category_label("unknown"), do: "Unknown"
  defp format_category_label(other), do: Phoenix.Naming.humanize(other)

  defp category_color("movie_not_ready"), do: "#f59e0b"
  defp category_color("duplicate_movie_error"), do: "#ef4444"
  defp category_color("no_results"), do: "#8b5cf6"
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
    |> Repo.all()
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
    |> Repo.all()
    |> Enum.map(fn movie ->
      confidence = get_in(movie.metadata || %{}, ["match_confidence"]) || 0.0

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
    |> Repo.all()
    |> Enum.map(fn movie ->
      source_title = get_in(movie.metadata || %{}, ["cinema_city_polish_title"])
      confidence = get_in(movie.metadata || %{}, ["match_confidence"]) || 0.8
      provider = get_in(movie.metadata || %{}, ["matched_by_provider"]) || "tmdb"

      movie
      |> Map.put(:source_title, source_title)
      |> Map.put(:confidence, confidence)
      |> Map.put(:provider, provider)
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
    |> Repo.all()
    |> fill_missing_hours(hours)
  end

  @doc """
  Get duplicate cinema_city_film_id count for data quality monitoring.
  """
  def get_duplicate_film_id_count do
    from(m in Movie,
      where: fragment("?->>'cinema_city_film_id' IS NOT NULL", m.metadata),
      group_by: fragment("?->>'cinema_city_film_id'", m.metadata),
      having: count() > 1,
      select: count()
    )
    |> Repo.all()
    |> length()
  end

  @doc """
  Get total movie count in database.
  """
  def get_total_movie_count do
    from(m in Movie, select: count())
    |> Repo.one() || 0
  end

  @doc """
  Get movies with Cinema City film IDs.
  """
  def get_cinema_city_movie_count do
    from(m in Movie,
      where: fragment("?->>'cinema_city_film_id' IS NOT NULL", m.metadata),
      select: count()
    )
    |> Repo.one() || 0
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
  Reject a movie match (remove cinema_city_film_id for re-matching).

  This clears the cinema_city_film_id from metadata so the next scraper run
  will attempt to re-match this movie with potentially better data.
  """
  def reject_movie_match(movie_id) do
    case Repo.get(Movie, movie_id) do
      nil ->
        {:error, :not_found}

      movie ->
        updated_metadata =
          (movie.metadata || %{})
          |> Map.delete("cinema_city_film_id")
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
