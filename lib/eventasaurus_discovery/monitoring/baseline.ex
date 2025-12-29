defmodule EventasaurusDiscovery.Monitoring.Baseline do
  @moduledoc """
  Programmatic API for creating and managing scraper performance baselines.

  Provides functions to establish statistical baselines for scraper performance
  that can be compared against future runs to measure improvement.

  ## Examples

      # Create a baseline for a source
      {:ok, baseline} = Baseline.create("cinema_city", hours: 24, limit: 500)

      # Save a baseline to file
      {:ok, filepath} = Baseline.save(baseline, "cinema_city")

      # Load a baseline from file
      {:ok, baseline} = Baseline.load("/path/to/baseline.json")

      # Calculate baseline from executions
      baseline = Baseline.calculate(executions, "cinema_city", from_time, to_time)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  import Ecto.Query

  # Legacy patterns - patterns are now generated dynamically in get_source_pattern/1

  @doc """
  Creates a baseline for a given source.

  ## Options

    * `:hours` - Number of hours to look back (default: 24)
    * `:limit` - Maximum number of executions to analyze (default: 500)

  ## Examples

      {:ok, baseline} = Baseline.create("cinema_city", hours: 48, limit: 200)
      {:error, :unknown_source} = Baseline.create("unknown_source")
      {:error, :no_executions} = Baseline.create("cinema_city")  # when no data exists
  """
  def create(source, opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    limit = Keyword.get(opts, :limit, 500)

    case get_source_pattern(source) do
      {:ok, worker_pattern} ->
        from_time = DateTime.add(DateTime.utc_now(), -hours, :hour)
        to_time = DateTime.utc_now()

        executions = fetch_executions(worker_pattern, from_time, to_time, limit)

        if Enum.empty?(executions) do
          {:error, :no_executions}
        else
          baseline = calculate(executions, source, from_time, to_time)
          {:ok, baseline}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Saves a baseline to a JSON file in the .taskmaster/baselines directory.

  Returns `{:ok, filepath}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, baseline} = Baseline.create("cinema_city")
      {:ok, filepath} = Baseline.save(baseline, "cinema_city")
      # => {:ok, ".taskmaster/baselines/cinema_city_20241123T120000.json"}
  """
  def save(baseline, source) do
    baselines_dir = Path.join([File.cwd!(), ".taskmaster", "baselines"])
    File.mkdir_p!(baselines_dir)

    timestamp =
      baseline.generated_at
      |> DateTime.to_iso8601(:basic)
      |> String.replace(":", "")

    filename = "#{source}_#{timestamp}.json"
    filepath = Path.join(baselines_dir, filename)

    case Jason.encode(baseline, pretty: true) do
      {:ok, json} ->
        case File.write(filepath, json) do
          :ok -> {:ok, filepath}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Loads a baseline from a JSON file.

  Returns `{:ok, baseline}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, baseline} = Baseline.load(".taskmaster/baselines/cinema_city_20241123.json")
  """
  def load(filepath) do
    case File.read(filepath) do
      {:ok, contents} ->
        Jason.decode(contents)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculates baseline metrics from a list of job executions.

  Returns a map containing:
    * `:source` - Source identifier
    * `:sample_size` - Number of executions analyzed
    * `:period_start` - Start of analysis period
    * `:period_end` - End of analysis period
    * `:success_rate` - Percentage of successful executions
    * `:ci_margin` - 95% confidence interval margin
    * `:completed` - Number of completed executions
    * `:failed` - Number of failed executions
    * `:cancelled` - Number of cancelled executions
    * `:error_categories` - Frequency map of error categories
    * `:avg_duration` - Average execution duration in ms
    * `:std_dev` - Standard deviation of durations
    * `:p50` - 50th percentile duration
    * `:p95` - 95th percentile duration
    * `:p99` - 99th percentile duration
    * `:chain_health` - Success rates by worker type
    * `:generated_at` - Timestamp of baseline creation
  """
  def calculate(executions, source, from_time, to_time) do
    total = length(executions)

    # Guard against empty executions list
    if total == 0 do
      raise ArgumentError, "Cannot calculate baseline from empty executions list"
    end

    # State distribution
    completed = Enum.count(executions, &(&1.state == "completed"))
    failed = Enum.count(executions, &(&1.state == "discarded"))
    cancelled = Enum.count(executions, &(&1.state == "cancelled"))

    success_rate = completed / total * 100

    # 95% confidence interval using Wilson score interval
    z = 1.96
    p = completed / total
    n = total

    ci_margin =
      z * :math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n) * 100

    # Error distribution
    error_categories =
      executions
      |> Enum.filter(&(&1.state != "completed"))
      |> Enum.map(& &1.results["error_category"])
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_cat, count} -> -count end)

    # Performance metrics (durations in ms)
    durations =
      executions
      |> Enum.map(& &1.duration_ms)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    avg_duration = if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0

    std_dev = calculate_std_dev(durations, avg_duration)

    p50 = percentile(durations, 0.50)
    p95 = percentile(durations, 0.95)
    p99 = percentile(durations, 0.99)

    # Job chain health (group by worker type)
    chain_health =
      executions
      |> Enum.group_by(& &1.worker)
      |> Enum.map(fn {worker, jobs} ->
        worker_total = length(jobs)
        worker_completed = Enum.count(jobs, &(&1.state == "completed"))
        # Guard against division by zero (should never happen, but defensive)
        worker_rate = if worker_total > 0, do: worker_completed / worker_total * 100, else: 0.0

        %{
          name: worker |> String.split(".") |> List.last(),
          success_rate: worker_rate,
          completed: worker_completed,
          total: worker_total
        }
      end)
      |> Enum.sort_by(fn %{success_rate: rate} -> -rate end)

    %{
      source: source,
      sample_size: total,
      period_start: from_time,
      period_end: to_time,
      success_rate: success_rate,
      ci_margin: ci_margin,
      completed: completed,
      failed: failed,
      cancelled: cancelled,
      error_categories: error_categories,
      avg_duration: avg_duration,
      std_dev: std_dev,
      p50: p50,
      p95: p95,
      p99: p99,
      chain_health: chain_health,
      generated_at: DateTime.utc_now()
    }
  end

  # Private helpers

  # Dynamically generate worker pattern from source name
  # e.g., "cinema_city" -> "EventasaurusDiscovery.Sources.CinemaCity.Jobs.%"
  defp get_source_pattern(source) when is_binary(source) do
    module_name =
      source
      |> String.split("_")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")

    pattern = "EventasaurusDiscovery.Sources.#{module_name}.Jobs.%"
    {:ok, pattern}
  end

  defp get_source_pattern(_), do: {:error, :invalid_source}

  defp fetch_executions(worker_pattern, from_time, to_time, limit) do
    from(j in JobExecutionSummary,
      where: like(j.worker, ^worker_pattern),
      where: j.attempted_at >= ^from_time and j.attempted_at <= ^to_time,
      order_by: [desc: j.attempted_at],
      limit: ^limit
    )
    |> Repo.replica().all()
  end

  defp calculate_std_dev(durations, avg_duration) do
    if length(durations) > 1 do
      variance =
        durations
        |> Enum.map(&((&1 - avg_duration) * (&1 - avg_duration)))
        |> Enum.sum()
        |> Kernel./(length(durations) - 1)

      :math.sqrt(variance)
    else
      0
    end
  end

  defp percentile([], _p), do: 0

  defp percentile(sorted_list, p) do
    k = (length(sorted_list) - 1) * p
    f = floor(k)
    c = ceil(k)

    if f == c do
      Enum.at(sorted_list, round(k))
    else
      lower = Enum.at(sorted_list, f)
      upper = Enum.at(sorted_list, c)
      lower + (upper - lower) * (k - f)
    end
  end
end
