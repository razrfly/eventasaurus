defmodule EventasaurusApp.Monitoring.Stats do
  @moduledoc """
  Queries and calculates statistics for Oban jobs from the oban_jobs table.

  Provides functions to fetch execution history, success/failure counts,
  and other metrics for monitoring job health.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias Oban.Job

  @doc """
  Gets the last execution for a specific worker.

  Returns a map with:
  - attempted_at: When the job was last attempted
  - completed_at: When it completed (if it did)
  - state: Job state (:completed, :executing, :available, :retryable, :cancelled, :discarded)
  - errors: List of errors if any
  - args: Job arguments (useful for seeing what was processed)
  """
  def get_last_execution(worker_name) when is_binary(worker_name) do
    query =
      from j in Job,
        where: j.worker == ^worker_name,
        where: not is_nil(j.attempted_at),
        order_by: [desc: j.attempted_at],
        limit: 1,
        select: %{
          attempted_at: j.attempted_at,
          completed_at: j.completed_at,
          scheduled_at: j.scheduled_at,
          state: j.state,
          errors: j.errors,
          args: j.args,
          queue: j.queue
        }

    case Repo.one(query) do
      nil -> nil
      result -> format_execution_result(result)
    end
  end

  @doc """
  Gets statistics for the last 24 hours for a specific worker.

  Returns a map with:
  - total_runs: Total number of executions attempted
  - completed: Number of successfully completed jobs
  - failed: Number of failed jobs
  - executing: Number currently executing
  - success_rate: Percentage of successful runs (0-100)
  - avg_duration_seconds: Average execution time in seconds
  """
  def get_stats_24h(worker_name) when is_binary(worker_name) do
    time_ago = DateTime.utc_now() |> DateTime.add(-24, :hour)

    # Get counts by state
    counts_query =
      from j in Job,
        where: j.worker == ^worker_name,
        where: j.attempted_at > ^time_ago,
        group_by: j.state,
        select: {j.state, count(j.id)}

    counts = Repo.all(counts_query) |> Enum.into(%{})

    # Get average duration for completed jobs
    duration_query =
      from j in Job,
        where: j.worker == ^worker_name,
        where: j.attempted_at > ^time_ago,
        where: j.state == "completed",
        where: not is_nil(j.completed_at),
        select: avg(
          fragment(
            "EXTRACT(EPOCH FROM (? - ?))",
            j.completed_at,
            j.attempted_at
          )
        )

    avg_duration = Repo.one(duration_query) || Decimal.new(0)

    total_runs = Enum.reduce(counts, 0, fn {_state, count}, acc -> acc + count end)
    completed = Map.get(counts, "completed", 0)
    failed = Map.get(counts, "discarded", 0) + Map.get(counts, "retryable", 0)
    executing = Map.get(counts, "executing", 0)

    success_rate =
      if total_runs > 0 do
        Float.round(completed / total_runs * 100, 1)
      else
        0.0
      end

    %{
      total_runs: total_runs,
      completed: completed,
      failed: failed,
      executing: executing,
      success_rate: success_rate,
      avg_duration_seconds: avg_duration |> Decimal.to_float() |> Float.round(2)
    }
  end

  @doc """
  Gets the count of items processed in the last execution (if available in args).

  This looks for common patterns in job args like:
  - "events_found"
  - "items_processed"
  - "count"

  Returns nil if not found.
  """
  def get_items_processed(nil), do: nil

  def get_items_processed(%{args: args}) when is_map(args) do
    cond do
      Map.has_key?(args, "events_found") -> args["events_found"]
      Map.has_key?(args, "items_processed") -> args["items_processed"]
      Map.has_key?(args, "count") -> args["count"]
      true -> nil
    end
  end

  def get_items_processed(_), do: nil

  # Private Functions

  defp format_execution_result(result) do
    result
    |> Map.put(:items_processed, get_items_processed(result))
    |> Map.put(:duration_seconds, calculate_duration(result))
  end

  defp calculate_duration(%{attempted_at: attempted, completed_at: completed})
       when not is_nil(completed) do
    DateTime.diff(completed, attempted)
  end

  defp calculate_duration(_), do: nil
end
