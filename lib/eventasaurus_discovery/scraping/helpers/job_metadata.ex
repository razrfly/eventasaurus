defmodule EventasaurusDiscovery.Scraping.Helpers.JobMetadata do
  @moduledoc """
  Helper module for tracking job metadata in Oban.

  Uses Oban's built-in metadata system instead of separate scrape_logs table.
  Provides consistent interfaces for updating job status and tracking metrics.
  """

  require Logger
  # Repo: Used for Repo.replica() read-only queries (uses read replica for performance)
  alias EventasaurusApp.Repo
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  import Ecto.Query

  @doc """
  Updates metadata for an index job.
  """
  def update_index_job(job_id, metadata) when is_map(metadata) do
    update_job_metadata(job_id, %{
      type: "index",
      status: "completed",
      metadata: metadata,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Updates metadata for a detail job.
  """
  def update_detail_job(job_id, metadata) when is_map(metadata) do
    update_job_metadata(job_id, %{
      type: "detail",
      status: "completed",
      metadata: metadata,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Records an error in job metadata.
  """
  def update_error(job_id, error, context \\ %{}) do
    error_message =
      case error do
        %{message: msg} -> msg
        msg when is_binary(msg) -> msg
        other -> inspect(other)
      end

    update_job_metadata(job_id, %{
      status: "failed",
      error: error_message,
      context: context,
      failed_at: DateTime.utc_now()
    })
  end

  @doc """
  Records a job as skipped with a reason.
  """
  def mark_skipped(job_id, reason) do
    update_job_metadata(job_id, %{
      status: "skipped",
      skip_reason: reason,
      skipped_at: DateTime.utc_now()
    })
  end

  @doc """
  Records progress for long-running jobs.
  """
  def update_progress(job_id, current, total, message \\ nil) do
    pct =
      cond do
        is_number(total) and total > 0 -> Float.round(current / total * 100, 2)
        true -> 0.0
      end

    metadata = %{
      progress_current: current,
      progress_total: total,
      progress_percentage: pct,
      last_update: DateTime.utc_now()
    }

    metadata =
      if message do
        Map.put(metadata, :progress_message, message)
      else
        metadata
      end

    update_job_metadata(job_id, metadata)
  end

  @doc """
  Gets metadata for a specific job.
  """
  def get_job_metadata(job_id) do
    query =
      from(j in Oban.Job,
        where: j.id == ^job_id,
        select: j.meta
      )

    case JobRepo.one(query) do
      nil -> %{}
      meta -> meta
    end
  end

  @doc """
  Gets summary statistics for jobs by source and date range.
  Uses read replica for this read-heavy aggregation query.
  """
  def get_job_stats(source_id, start_date \\ nil, end_date \\ nil) do
    start_date = start_date || DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)
    end_date = end_date || DateTime.utc_now()

    query =
      from(j in Oban.Job,
        where: j.queue == "scraper",
        where: j.inserted_at >= ^start_date and j.inserted_at <= ^end_date,
        where: fragment("? @> ?", j.args, ^%{source_id: source_id}),
        select: %{
          state: j.state,
          count: count(j.id)
        },
        group_by: j.state
      )

    stats =
      Repo.replica().all(query)
      |> Enum.into(%{}, fn %{state: state, count: count} -> {state, count} end)

    %{
      completed: Map.get(stats, "completed", 0),
      failed: Map.get(stats, "retryable", 0) + Map.get(stats, "discarded", 0),
      pending: Map.get(stats, "available", 0) + Map.get(stats, "scheduled", 0),
      total: Enum.sum(Map.values(stats))
    }
  end

  @doc """
  Cleans up old job metadata older than specified days.
  """
  def cleanup_old_metadata(days_to_keep \\ 30) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_to_keep * 24 * 3600, :second)

    query =
      from(j in Oban.Job,
        where: j.completed_at < ^cutoff_date or j.discarded_at < ^cutoff_date,
        where: j.queue == "scraper"
      )

    {deleted_count, _} = JobRepo.delete_all(query)

    Logger.info("Cleaned up #{deleted_count} old scraper job records")
    deleted_count
  end

  # Private helper to update job metadata
  defp update_job_metadata(job_id, new_metadata) do
    query =
      from(j in Oban.Job,
        where: j.id == ^job_id
      )

    case JobRepo.one(query) do
      nil ->
        Logger.warning("Job #{job_id} not found for metadata update")
        {:error, :job_not_found}

      job ->
        # Merge new metadata with existing
        updated_meta = Map.merge(job.meta || %{}, new_metadata)

        # Update the job's metadata
        from(j in Oban.Job, where: j.id == ^job_id)
        |> JobRepo.update_all(set: [meta: updated_meta])

        Logger.debug("Updated metadata for job #{job_id}: #{inspect(new_metadata)}")
        :ok
    end
  end
end
