defmodule EventasaurusApp.Monitoring.HealthCheck do
  @moduledoc """
  Determines health status for Oban jobs based on execution metrics.

  Health statuses:
  - :healthy (green) - Job running as expected
  - :warning (yellow) - Job showing concerning patterns
  - :error (red) - Job failing or not running when it should be
  """

  @doc """
  Determines health status for a job based on its config and recent execution data.

  Health determination logic:
  - :error if:
    * Scheduled job hasn't run in 2x its expected interval
    * Success rate < 50% in last 24h
    * Last execution failed and no successful runs recently
  - :warning if:
    * Success rate between 50-90%
    * Scheduled job hasn't run in 1.5x its expected interval
    * High error count relative to success count
  - :healthy otherwise
  """
  @spec determine_health(map(), map() | nil, map()) :: :healthy | :warning | :error

  # No execution data at all - this is an error for scheduled jobs, warning for others
  def determine_health(%{category: :scheduled, schedule: schedule}, nil, %{total_runs: 0})
      when not is_nil(schedule) do
    :error
  end

  def determine_health(_job_config, nil, %{total_runs: 0}) do
    :warning
  end

  # Has execution data - analyze it
  def determine_health(job_config, last_execution, stats_24h) do
    checks = [
      check_success_rate(stats_24h),
      check_last_execution_state(last_execution),
      check_scheduled_job_freshness(job_config, last_execution),
      check_error_ratio(stats_24h)
    ]

    # If any check returns :error, overall status is :error
    # If any check returns :warning, overall status is :warning
    # Otherwise :healthy
    cond do
      Enum.member?(checks, :error) -> :error
      Enum.member?(checks, :warning) -> :warning
      true -> :healthy
    end
  end

  # Private health check functions

  # Check success rate in last 24h
  defp check_success_rate(%{success_rate: rate, total_runs: total}) when total > 0 do
    cond do
      rate < 50.0 -> :error
      rate < 90.0 -> :warning
      true -> :healthy
    end
  end

  defp check_success_rate(_), do: :healthy

  # Check if last execution succeeded
  defp check_last_execution_state(%{state: "completed"}), do: :healthy
  defp check_last_execution_state(%{state: "executing"}), do: :healthy
  defp check_last_execution_state(%{state: "available"}), do: :healthy
  defp check_last_execution_state(%{state: "scheduled"}), do: :healthy
  defp check_last_execution_state(%{state: "retryable"}), do: :warning
  defp check_last_execution_state(%{state: "discarded"}), do: :error
  defp check_last_execution_state(%{state: "cancelled"}), do: :warning
  defp check_last_execution_state(_), do: :healthy

  # Check if scheduled job has run recently enough
  defp check_scheduled_job_freshness(
         %{category: :scheduled, schedule: schedule},
         %{attempted_at: attempted_at}
       )
       when not is_nil(schedule) do
    interval_minutes = estimate_schedule_interval(schedule)
    age_minutes = DateTime.diff(DateTime.utc_now(), attempted_at, :minute)

    cond do
      # Hasn't run in 2x the expected interval
      age_minutes > interval_minutes * 2 -> :error
      # Hasn't run in 1.5x the expected interval
      age_minutes > interval_minutes * 1.5 -> :warning
      true -> :healthy
    end
  end

  defp check_scheduled_job_freshness(_job_config, _last_execution), do: :healthy

  # Check if error count is concerning relative to success count
  defp check_error_ratio(%{completed: completed, failed: failed}) when completed + failed > 0 do
    total = completed + failed
    error_rate = failed / total * 100

    cond do
      error_rate > 50.0 -> :error
      error_rate > 10.0 -> :warning
      true -> :healthy
    end
  end

  defp check_error_ratio(_), do: :healthy

  # Estimate interval in minutes from cron expression
  # This is a simple heuristic - doesn't parse full cron syntax
  defp estimate_schedule_interval(schedule) do
    case schedule do
      # Hourly patterns
      "0 * * * *" -> 60
      # Daily patterns
      "0 " <> _rest -> 24 * 60
      "@daily" -> 24 * 60
      "@hourly" -> 60
      "@weekly" -> 7 * 24 * 60
      # Default to daily if unknown
      _ -> 24 * 60
    end
  end
end
