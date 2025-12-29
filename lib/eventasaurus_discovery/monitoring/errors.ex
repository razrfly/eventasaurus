defmodule EventasaurusDiscovery.Monitoring.Errors do
  @moduledoc """
  Programmatic API for analyzing error patterns and categorization for scrapers.

  Provides functions to analyze error types, frequencies, and trends to help
  identify root causes and prioritize fixes.

  ## Examples

      # Analyze errors for a source
      {:ok, analysis} = Errors.analyze("cinema_city", hours: 24, limit: 20)

      # Get error summary
      summary = Errors.summary(analysis)
      # => %{total_failures: 14, error_rate: 11.0, ...}

      # Get top error messages
      top_errors = Errors.top_messages(analysis, 10)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  import Ecto.Query

  @source_patterns %{
    "cinema_city" => "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%",
    "repertuary" => "EventasaurusDiscovery.Sources.Repertuary.Jobs.%",
    "karnet" => "EventasaurusDiscovery.Sources.Karnet.Jobs.%",
    "week_pl" => "EventasaurusDiscovery.Sources.WeekPl.Jobs.%",
    "bandsintown" => "EventasaurusDiscovery.Sources.Bandsintown.Jobs.%",
    "resident_advisor" => "EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.%",
    "sortiraparis" => "EventasaurusDiscovery.Sources.Sortiraparis.Jobs.%",
    "inquizition" => "EventasaurusDiscovery.Sources.Inquizition.Jobs.%",
    "waw4free" => "EventasaurusDiscovery.Sources.Waw4Free.Jobs.%"
  }

  @doc """
  Analyzes errors for a given source over a time period.

  ## Options

    * `:hours` - Number of hours to look back (default: 24)
    * `:limit` - Maximum number of error messages to return (default: 20)
    * `:category` - Filter by specific error category (optional)

  ## Examples

      {:ok, analysis} = Errors.analyze("cinema_city", hours: 48, limit: 10)
      {:ok, analysis} = Errors.analyze("cinema_city", category: "network_error")
      {:error, :unknown_source} = Errors.analyze("invalid")
  """
  def analyze(source, opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    limit = Keyword.get(opts, :limit, 20)
    category_filter = Keyword.get(opts, :category)

    case get_source_pattern(source) do
      {:ok, worker_pattern} ->
        from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)

        # Query failed executions
        base_query =
          from(j in JobExecutionSummary,
            where: like(j.worker, ^worker_pattern),
            where: j.attempted_at >= ^from_time,
            where: j.state in ["discarded", "cancelled"]
          )

        # Apply category filter if specified
        query =
          if category_filter do
            from(j in base_query,
              where: fragment("?->>'error_category' = ?", j.results, ^category_filter)
            )
          else
            base_query
          end

        failures = Repo.replica().all(query)

        # Get total executions for context
        total_executions =
          from(j in JobExecutionSummary,
            where: like(j.worker, ^worker_pattern),
            where: j.attempted_at >= ^from_time,
            select: count(j.id)
          )
          |> Repo.replica().one()

        if Enum.empty?(failures) do
          {:ok,
           %{
             source: source,
             hours: hours,
             total_failures: 0,
             total_executions: total_executions,
             error_rate: 0.0,
             category_distribution: [],
             error_messages: [],
             timeline: [],
             affected_jobs: []
           }}
        else
          analysis = analyze_errors(failures, total_executions, hours, source, limit)
          {:ok, analysis}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns a summary of the error analysis.

  ## Examples

      {:ok, analysis} = Errors.analyze("cinema_city")
      summary = Errors.summary(analysis)
      # => %{total_failures: 14, error_rate: 11.0, top_category: "network_error"}
  """
  def summary(analysis) do
    top_category =
      case analysis.category_distribution do
        [{category, _count} | _] -> category
        [] -> nil
      end

    %{
      total_failures: analysis.total_failures,
      total_executions: analysis.total_executions,
      error_rate: analysis.error_rate,
      top_category: top_category,
      unique_error_types: length(analysis.error_messages)
    }
  end

  @doc """
  Returns the top N error messages from the analysis.

  ## Examples

      {:ok, analysis} = Errors.analyze("cinema_city")
      top_errors = Errors.top_messages(analysis, 5)
      # => [{{category, message}, count}, ...]
  """
  def top_messages(analysis, limit) do
    Enum.take(analysis.error_messages, limit)
  end

  @doc """
  Returns error recommendations based on analysis.

  ## Examples

      {:ok, analysis} = Errors.analyze("cinema_city")
      recommendations = Errors.recommendations(analysis)
      # => %{"network_error" => "Consider implementing retry logic...", ...}
  """
  def recommendations(analysis) do
    analysis.category_distribution
    |> Enum.take(3)
    |> Map.new(fn {category, _count} ->
      {category, get_recommendation(category)}
    end)
  end

  # Private helpers

  defp get_source_pattern(source) do
    case Map.fetch(@source_patterns, source) do
      {:ok, pattern} -> {:ok, pattern}
      :error -> {:error, :unknown_source}
    end
  end

  defp analyze_errors(failures, total_executions, hours, source, limit) do
    total_failures = length(failures)
    error_rate = total_failures / total_executions * 100

    # Category distribution
    category_distribution =
      failures
      |> Enum.map(& &1.results["error_category"])
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_cat, count} -> -count end)

    # Top error messages (group by error message)
    error_messages =
      failures
      |> Enum.map(fn f ->
        {f.results["error_category"], f.error}
      end)
      |> Enum.reject(fn {_cat, msg} -> is_nil(msg) end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_msg, count} -> -count end)
      |> Enum.take(limit)

    # Timeline (group by hour)
    timeline =
      failures
      |> Enum.group_by(fn f ->
        f.attempted_at
        |> DateTime.truncate(:second)
        |> Map.put(:minute, 0)
        |> Map.put(:second, 0)
      end)
      |> Enum.map(fn {hour, errors} -> {hour, length(errors)} end)
      |> Enum.sort_by(fn {hour, _} -> hour end)

    # Most affected jobs
    affected_jobs =
      failures
      |> Enum.group_by(& &1.worker)
      |> Enum.map(fn {worker, job_failures} ->
        worker_name = worker |> String.split(".") |> List.last()
        failure_count = length(job_failures)

        # Get total executions for this worker
        worker_total =
          from(j in JobExecutionSummary,
            where: j.worker == ^worker,
            where: j.attempted_at >= ^DateTime.add(DateTime.utc_now(), -hours, :hour),
            select: count(j.id)
          )
          |> Repo.replica().one()

        error_rate = failure_count / worker_total * 100
        {worker_name, failure_count, error_rate}
      end)
      |> Enum.sort_by(fn {_, count, _} -> -count end)

    %{
      source: source,
      hours: hours,
      total_failures: total_failures,
      total_executions: total_executions,
      error_rate: error_rate,
      category_distribution: category_distribution,
      error_messages: error_messages,
      timeline: timeline,
      affected_jobs: affected_jobs
    }
  end

  defp get_recommendation(category) do
    # 12 standard categories + 1 fallback (uncategorized_error)
    case category do
      "validation_error" ->
        "Add upstream validation before processing"

      "parsing_error" ->
        "Review HTML/JSON structure changes, add fallback parsing strategies"

      "data_quality_error" ->
        "Add data quality checks and handle site structure changes"

      "data_integrity_error" ->
        "Review database constraints and transaction handling"

      "dependency_error" ->
        "Add dependency health checks and graceful waiting/retry logic"

      "network_error" ->
        "Consider implementing retry logic with exponential backoff"

      "rate_limit_error" ->
        "Implement request throttling and respect rate limit headers"

      "authentication_error" ->
        "Verify API credentials and token refresh logic"

      "geocoding_error" ->
        "Implement fallback geocoding providers"

      "venue_error" ->
        "Improve venue matching algorithms or add manual verification"

      "performer_error" ->
        "Enhance performer/artist matching logic"

      "tmdb_error" ->
        "Check TMDB API quotas and implement caching for movie lookups"

      "uncategorized_error" ->
        "Review error logs and add specific error handling"

      # Legacy categories (for historical data compatibility)
      "unknown_error" ->
        "Review error logs and add specific error handling"

      "category_error" ->
        "Review and expand event categorization rules"

      "duplicate_error" ->
        "Fine-tune deduplication logic"

      _ ->
        "Review error logs and add specific error handling"
    end
  end
end
