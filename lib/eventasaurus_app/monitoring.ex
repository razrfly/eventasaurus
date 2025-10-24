defmodule EventasaurusApp.Monitoring do
  @moduledoc """
  Context module for monitoring Oban jobs and background workers.

  Provides functionality to track job execution, calculate metrics,
  and determine health status for all registered Oban workers.
  """

  alias EventasaurusApp.Monitoring.{JobRegistry, Stats, HealthCheck}

  @doc """
  Returns a list of all registered jobs with their current stats and health status.

  Returns a list of maps with the following structure:
    %{
      worker: "Module.Name",
      display_name: "Friendly Name",
      category: :discovery | :scheduled | :queue | :background,
      queue: "queue_name",
      schedule: nil | "cron expression",
      health_status: :healthy | :warning | :error,
      last_execution: %{...},
      stats_24h: %{...}
    }
  """
  def get_all_job_stats do
    JobRegistry.list_all_jobs()
    |> Enum.filter(fn job -> Map.get(job, :show_in_dashboard, true) end)
    |> Enum.map(&enrich_job_with_stats/1)
    |> Enum.sort_by(& &1.category)
  end

  @doc """
  Returns detailed stats for a specific worker.
  """
  def get_job_stats(worker_name) when is_binary(worker_name) do
    case JobRegistry.get_job_config(worker_name) do
      nil -> {:error, :not_found}
      job_config -> {:ok, enrich_job_with_stats(job_config)}
    end
  end

  @doc """
  Returns summary statistics across all jobs.
  """
  def get_summary_stats do
    all_stats = get_all_job_stats()

    %{
      total_jobs: length(all_stats),
      healthy: Enum.count(all_stats, &(&1.health_status == :healthy)),
      warning: Enum.count(all_stats, &(&1.health_status == :warning)),
      error: Enum.count(all_stats, &(&1.health_status == :error)),
      discovery_jobs: Enum.count(all_stats, &(&1.category == :discovery)),
      scheduled_jobs: Enum.count(all_stats, &(&1.category == :scheduled)),
      maintenance_jobs: Enum.count(all_stats, &(&1.category == :maintenance))
    }
  end

  # Private Functions

  defp enrich_job_with_stats(job_config) do
    worker = job_config.worker

    # Get execution stats from Oban jobs table
    last_execution = Stats.get_last_execution(worker)
    stats_24h = Stats.get_stats_24h(worker)

    # Determine health status
    health_status = HealthCheck.determine_health(job_config, last_execution, stats_24h)

    job_config
    |> Map.put(:health_status, health_status)
    |> Map.put(:last_execution, last_execution)
    |> Map.put(:stats_24h, stats_24h)
  end
end
