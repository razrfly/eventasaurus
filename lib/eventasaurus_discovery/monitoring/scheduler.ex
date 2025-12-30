defmodule EventasaurusDiscovery.Monitoring.Scheduler do
  @moduledoc """
  Programmatic API for scheduler health monitoring.

  Audits whether SyncJobs are running daily as scheduled and identifies
  gaps in execution or failures. Used by both the mix task and dashboard.

  ## Examples

      # Check scheduler health for last 7 days
      {:ok, health} = Scheduler.check(days: 7)

      # Check specific source only
      {:ok, health} = Scheduler.check(days: 7, source: "cinema_city")

      # Get alerts from health data
      alerts = Scheduler.alerts(health)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  import Ecto.Query

  @typedoc "Alert severity type"
  @type alert_type :: :missing | :failure | :stale | :no_executions

  @typedoc "Individual alert"
  @type alert :: %{
          source: String.t(),
          type: alert_type(),
          message: String.t(),
          date: Date.t() | nil
        }

  @typedoc "Day execution summary"
  @type day_execution :: %{
          date: Date.t(),
          status: :ok | :failure | :missing,
          executions: [map()],
          latest: map() | nil,
          jobs_spawned: non_neg_integer() | nil,
          duration_ms: non_neg_integer() | nil,
          error_message: String.t() | nil
        }

  @typedoc "Source health result"
  @type source_health :: %{
          source: String.t(),
          display_name: String.t(),
          days: [day_execution()],
          total_executions: non_neg_integer(),
          successful: non_neg_integer(),
          failed: non_neg_integer(),
          success_rate: float(),
          has_recent_execution: boolean(),
          last_execution_hours_ago: non_neg_integer() | nil,
          alerts: [alert()]
        }

  @typedoc "Overall scheduler health result"
  @type scheduler_health :: %{
          sources: [source_health()],
          period_start: Date.t(),
          period_end: Date.t(),
          days: non_neg_integer(),
          total_alerts: non_neg_integer()
        }

  @sources %{
    "cinema_city" => %{
      pattern: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
      display_name: "Cinema City",
      child_job_key: "jobs_scheduled"
    },
    "repertuary" => %{
      pattern: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob",
      display_name: "Repertuary",
      child_job_key: "movie_jobs_scheduled"
    }
  }

  @doc """
  Returns the configured sources for scheduler monitoring.
  """
  @spec sources() :: %{String.t() => map()}
  def sources, do: @sources

  @doc """
  Checks scheduler health for configured sources.

  ## Options

    * `:days` - Number of days to look back (default: 7)
    * `:source` - Specific source to check (default: all sources)

  ## Examples

      {:ok, health} = Scheduler.check(days: 7)
      {:ok, health} = Scheduler.check(days: 14, source: "cinema_city")
      {:error, :unknown_source} = Scheduler.check(source: "invalid")
  """
  @spec check(keyword()) :: {:ok, scheduler_health()} | {:error, atom()}
  def check(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    source = Keyword.get(opts, :source)

    # Validate source if provided
    if source && !Map.has_key?(@sources, source) do
      {:error, :unknown_source}
    else
      sources_to_check =
        if source do
          [{source, @sources[source]}]
        else
          Map.to_list(@sources)
        end

      period_start = days_ago(days)
      period_end = Date.utc_today()

      source_results =
        Enum.map(sources_to_check, fn {source_key, config} ->
          check_source_health(source_key, config, days)
        end)

      total_alerts =
        source_results
        |> Enum.flat_map(& &1.alerts)
        |> length()

      {:ok,
       %{
         sources: source_results,
         period_start: period_start,
         period_end: period_end,
         days: days,
         total_alerts: total_alerts
       }}
    end
  end

  @doc """
  Extracts all alerts from scheduler health data.

  ## Examples

      {:ok, health} = Scheduler.check()
      alerts = Scheduler.alerts(health)
      # => [%{source: "cinema_city", type: :missing, message: "...", date: ~D[...]}, ...]
  """
  @spec alerts(scheduler_health()) :: [alert()]
  def alerts(%{sources: sources}) do
    Enum.flat_map(sources, & &1.alerts)
  end

  @doc """
  Checks if all sources are healthy (no alerts).

  ## Examples

      {:ok, health} = Scheduler.check()
      Scheduler.healthy?(health)
      # => true
  """
  @spec healthy?(scheduler_health()) :: boolean()
  def healthy?(%{total_alerts: 0}), do: true
  def healthy?(_), do: false

  @doc """
  Returns sources with critical alerts (missing or stale executions).
  """
  @spec critical_sources(scheduler_health()) :: [String.t()]
  def critical_sources(%{sources: sources}) do
    sources
    |> Enum.filter(fn source ->
      Enum.any?(source.alerts, fn alert ->
        alert.type in [:missing, :stale, :no_executions]
      end)
    end)
    |> Enum.map(& &1.source)
  end

  # Private helpers

  defp check_source_health(source_key, config, days) do
    from_date = days_ago(days)
    executions = fetch_sync_job_executions(config.pattern, from_date)

    if Enum.empty?(executions) do
      %{
        source: source_key,
        display_name: config.display_name,
        days: generate_empty_days(days),
        total_executions: 0,
        successful: 0,
        failed: 0,
        success_rate: 0.0,
        has_recent_execution: false,
        last_execution_hours_ago: nil,
        alerts: [
          %{
            source: source_key,
            type: :no_executions,
            message: "No executions found in last #{days} days",
            date: nil
          }
        ]
      }
    else
      by_date = group_by_date(executions)
      expected_dates = generate_date_range(days)

      # Build day-by-day results
      day_results =
        Enum.map(expected_dates, fn date ->
          case Map.get(by_date, date) do
            nil ->
              %{
                date: date,
                status: :missing,
                executions: [],
                latest: nil,
                jobs_spawned: nil,
                duration_ms: nil,
                error_message: nil
              }

            execs ->
              latest = Enum.max_by(execs, & &1.attempted_at)

              status =
                if latest.state == "completed", do: :ok, else: :failure

              jobs_spawned = get_in(latest.results || %{}, [config.child_job_key])

              error_message =
                if latest.state != "completed" do
                  get_in(latest.results || %{}, ["error_message"])
                end

              %{
                date: date,
                status: status,
                executions: execs,
                latest: latest,
                jobs_spawned: jobs_spawned,
                duration_ms: latest.duration_ms,
                error_message: error_message
              }
          end
        end)

      # Calculate statistics
      total = length(executions)
      successful = Enum.count(executions, &(&1.state == "completed"))
      failed = total - successful
      success_rate = if total > 0, do: Float.round(successful / total * 100, 1), else: 0.0

      # Check for recent execution
      recent_cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

      has_recent =
        Enum.any?(executions, fn exec ->
          DateTime.compare(exec.attempted_at, recent_cutoff) == :gt
        end)

      last_exec = Enum.max_by(executions, & &1.attempted_at)
      hours_ago = div(DateTime.diff(DateTime.utc_now(), last_exec.attempted_at), 3600)

      # Generate alerts
      alerts = build_alerts(source_key, day_results, has_recent, hours_ago)

      %{
        source: source_key,
        display_name: config.display_name,
        days: day_results,
        total_executions: total,
        successful: successful,
        failed: failed,
        success_rate: success_rate,
        has_recent_execution: has_recent,
        last_execution_hours_ago: hours_ago,
        alerts: alerts
      }
    end
  end

  defp build_alerts(source_key, day_results, has_recent, hours_ago) do
    # Alerts for missing or failed days
    day_alerts =
      Enum.flat_map(day_results, fn day ->
        case day.status do
          :missing ->
            [
              %{
                source: source_key,
                type: :missing,
                message: "Missing execution on #{format_date(day.date)}",
                date: day.date
              }
            ]

          :failure ->
            error_preview =
              if day.error_message do
                String.slice(day.error_message, 0, 50)
              else
                "Unknown error"
              end

            [
              %{
                source: source_key,
                type: :failure,
                message: "Failed on #{format_date(day.date)}: #{error_preview}",
                date: day.date
              }
            ]

          :ok ->
            []
        end
      end)

    # Alert for stale execution
    stale_alerts =
      if has_recent do
        []
      else
        [
          %{
            source: source_key,
            type: :stale,
            message: "No execution in last 24 hours (last run: #{hours_ago}h ago)",
            date: nil
          }
        ]
      end

    day_alerts ++ stale_alerts
  end

  defp generate_empty_days(days) do
    generate_date_range(days)
    |> Enum.map(fn date ->
      %{
        date: date,
        status: :missing,
        executions: [],
        latest: nil,
        jobs_spawned: nil,
        duration_ms: nil,
        error_message: nil
      }
    end)
  end

  defp fetch_sync_job_executions(worker_pattern, from_date) do
    from_datetime = DateTime.new!(from_date, ~T[00:00:00], "Etc/UTC")

    from(j in JobExecutionSummary,
      where: j.worker == ^worker_pattern,
      where: j.attempted_at >= ^from_datetime,
      order_by: [desc: j.attempted_at]
    )
    |> Repo.replica().all()
  end

  defp group_by_date(executions) do
    Enum.group_by(executions, fn exec ->
      DateTime.to_date(exec.attempted_at)
    end)
  end

  defp days_ago(days) do
    Date.add(Date.utc_today(), -days + 1)
  end

  defp generate_date_range(days) do
    today = Date.utc_today()

    (days - 1)..0//-1
    |> Enum.map(fn offset -> Date.add(today, -offset) end)
  end

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end
end
