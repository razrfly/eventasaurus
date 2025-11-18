defmodule EventasaurusDiscovery.JobExecutionSummaries.Lineage do
  @moduledoc """
  Query functions for job lineage tracking and pipeline visualization.

  Provides recursive CTE queries to traverse parent-child relationships between jobs,
  enabling visualization of multi-step job pipelines and debugging of complex workflows.

  ## Use Cases

  - Trace failed ShowtimeProcessJobs back to originating SyncJob
  - Visualize complete pipeline structure for any job
  - Find all children spawned by a coordinator job
  - Identify failure points in a pipeline
  - Calculate pipeline health metrics

  ## Parent Tracking

  Jobs track their parent using `parent_job_id` in the `results` JSONB field:

      %{
        "parent_job_id" => 12345,  # ID of the job that spawned this one
        "pipeline_id" => "sync_20241118",  # Optional batch identifier
        ...
      }

  ## Example

      # Get full tree for a job
      tree = Lineage.get_job_tree(12345)

      # Find all descendants
      children = Lineage.get_descendants(12345)

      # Calculate pipeline health
      health = Lineage.get_pipeline_health(12345)
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  @doc """
  Get the full job tree (ancestors + job + descendants) for a given job ID.

  Returns a map with:
  - `:ancestors` - List of parent jobs up to root
  - `:job` - The job itself
  - `:descendants` - List of all child jobs (recursively)

  ## Examples

      iex> Lineage.get_job_tree(12345)
      %{
        ancestors: [%JobExecutionSummary{}, ...],
        job: %JobExecutionSummary{id: 12345},
        descendants: [%JobExecutionSummary{}, ...]
      }
  """
  def get_job_tree(job_id) do
    job = Repo.get(JobExecutionSummary, job_id)

    if job do
      %{
        ancestors: get_ancestors(job_id),
        job: job,
        descendants: get_descendants(job_id)
      }
    else
      nil
    end
  end

  @doc """
  Get all ancestor jobs (parent, grandparent, etc.) using recursive CTE.

  Returns a list of jobs ordered from immediate parent to root (oldest ancestor).

  ## Examples

      iex> Lineage.get_ancestors(12345)
      [
        %JobExecutionSummary{id: 12344, ...},  # parent
        %JobExecutionSummary{id: 12340, ...},  # grandparent
        %JobExecutionSummary{id: 12300, ...}   # root
      ]
  """
  def get_ancestors(job_id) do
    # Recursive CTE to walk up the parent chain
    initial_query =
      from(s in JobExecutionSummary,
        where: s.id == ^job_id,
        select: %{
          id: s.id,
          parent_id: fragment("(? ->> 'parent_job_id')::bigint", s.results),
          depth: 0
        }
      )

    recursive_query =
      from(s in JobExecutionSummary,
        join: a in "ancestors_cte",
        on: s.id == fragment("?::bigint", a.parent_id),
        where: not is_nil(a.parent_id),
        select: %{
          id: s.id,
          parent_id: fragment("(? ->> 'parent_job_id')::bigint", s.results),
          depth: a.depth + 1
        }
      )

    # Execute recursive CTE
    cte_query =
      initial_query
      |> union_all(^recursive_query)

    from(s in JobExecutionSummary,
      join: a in subquery({"ancestors_cte", cte_query}),
      on: s.id == a.id,
      where: a.depth > 0,
      order_by: [asc: a.depth],
      select: s
    )
    |> Repo.all()
  end

  @doc """
  Get all descendant jobs (children, grandchildren, etc.) using recursive CTE.

  Returns a list of jobs ordered by depth (immediate children first).

  ## Examples

      iex> Lineage.get_descendants(12345)
      [
        %JobExecutionSummary{id: 12346, ...},  # child
        %JobExecutionSummary{id: 12347, ...},  # child
        %JobExecutionSummary{id: 12348, ...},  # grandchild
        ...
      ]
  """
  def get_descendants(job_id) do
    # Recursive CTE to walk down the child chain
    initial_query =
      from(s in JobExecutionSummary,
        where: s.id == ^job_id,
        select: %{
          id: s.id,
          depth: 0
        }
      )

    recursive_query =
      from(s in JobExecutionSummary,
        join: d in "descendants_cte",
        on: fragment("(? ->> 'parent_job_id')::bigint", s.results) == d.id,
        select: %{
          id: s.id,
          depth: d.depth + 1
        }
      )

    # Execute recursive CTE
    cte_query =
      initial_query
      |> union_all(^recursive_query)

    from(s in JobExecutionSummary,
      join: d in subquery({"descendants_cte", cte_query}),
      on: s.id == d.id,
      where: d.depth > 0,
      order_by: [asc: d.depth, desc: s.attempted_at],
      select: s
    )
    |> Repo.all()
  end

  @doc """
  Get sibling jobs (jobs with the same parent).

  Returns a list of jobs that share the same parent as the given job.
  Excludes the job itself from the results.

  ## Examples

      iex> Lineage.get_siblings(12345)
      [
        %JobExecutionSummary{id: 12346, ...},
        %JobExecutionSummary{id: 12347, ...}
      ]
  """
  def get_siblings(job_id) do
    job = Repo.get(JobExecutionSummary, job_id)

    if job do
      parent_id = get_in(job.results, ["parent_job_id"])

      if parent_id do
        from(s in JobExecutionSummary,
          where: fragment("(? ->> 'parent_job_id')::bigint", s.results) == ^parent_id,
          where: s.id != ^job_id,
          order_by: [desc: s.attempted_at]
        )
        |> Repo.all()
      else
        []
      end
    else
      []
    end
  end

  @doc """
  Get all jobs in a pipeline by pipeline_id or batch_id.

  Returns all jobs that share the same pipeline identifier, ordered by attempted_at.

  ## Examples

      iex> Lineage.get_pipeline_jobs("sync_20241118")
      [%JobExecutionSummary{}, ...]
  """
  def get_pipeline_jobs(pipeline_id) when is_binary(pipeline_id) do
    from(s in JobExecutionSummary,
      where: fragment("? ->> 'pipeline_id' = ?", s.results, ^pipeline_id),
      order_by: [desc: s.attempted_at]
    )
    |> Repo.all()
  end

  @doc """
  Find failure points in a pipeline.

  Given a root job ID, returns all failed/discarded jobs in the pipeline tree.
  Useful for debugging multi-step workflows.

  Returns a list of failed jobs with their position in the pipeline.

  ## Examples

      iex> Lineage.find_pipeline_failures(12345)
      [
        %{job: %JobExecutionSummary{state: "discarded"}, depth: 3, ancestors: [...]},
        ...
      ]
  """
  def find_pipeline_failures(root_job_id) do
    descendants = get_descendants(root_job_id)

    descendants
    |> Enum.filter(&(&1.state in ["discarded", "cancelled"]))
    |> Enum.map(fn job ->
      %{
        job: job,
        ancestors: get_ancestors(job.id),
        error: job.error
      }
    end)
  end

  @doc """
  Calculate pipeline health metrics for a root job.

  Given a coordinator job ID, calculates aggregate metrics for the entire pipeline:
  - total_jobs: Total number of jobs in pipeline (including root)
  - completed: Number of completed jobs
  - failed: Number of failed/discarded jobs
  - retryable: Number of jobs waiting to retry
  - success_rate: Percentage of successful jobs
  - avg_duration_ms: Average job duration
  - max_depth: Maximum pipeline depth

  ## Examples

      iex> Lineage.get_pipeline_health(12345)
      %{
        total_jobs: 150,
        completed: 140,
        failed: 10,
        retryable: 0,
        success_rate: 93.33,
        avg_duration_ms: 2500.0,
        max_depth: 3
      }
  """
  def get_pipeline_health(root_job_id) do
    root_job = Repo.get(JobExecutionSummary, root_job_id)
    descendants = get_descendants(root_job_id)
    all_jobs = [root_job | descendants]

    total = length(all_jobs)
    completed = Enum.count(all_jobs, &(&1.state == "completed"))
    failed = Enum.count(all_jobs, &(&1.state in ["discarded", "cancelled"]))
    retryable = Enum.count(all_jobs, &(&1.state == "retryable"))

    durations = Enum.map(all_jobs, & &1.duration_ms) |> Enum.reject(&is_nil/1)
    avg_duration = if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0

    success_rate = if total > 0, do: Float.round(completed / total * 100, 2), else: 0.0

    # Calculate max depth
    max_depth = calculate_max_depth(root_job_id)

    %{
      total_jobs: total,
      completed: completed,
      failed: failed,
      retryable: retryable,
      success_rate: success_rate,
      avg_duration_ms: Float.round(avg_duration, 2),
      max_depth: max_depth
    }
  end

  @doc """
  Get the root job (top-level coordinator) for any job in a pipeline.

  Walks up the ancestor chain to find the job with no parent.

  ## Examples

      iex> Lineage.get_root_job(12350)
      %JobExecutionSummary{id: 12300, ...}  # The SyncJob that started it all
  """
  def get_root_job(job_id) do
    ancestors = get_ancestors(job_id)

    if length(ancestors) > 0 do
      List.last(ancestors)
    else
      Repo.get(JobExecutionSummary, job_id)
    end
  end

  # Private helper functions

  # Calculate the maximum depth of a job tree
  defp calculate_max_depth(root_job_id) do
    # Recursive CTE to find max depth
    initial_query =
      from(s in JobExecutionSummary,
        where: s.id == ^root_job_id,
        select: %{id: s.id, depth: 0}
      )

    recursive_query =
      from(s in JobExecutionSummary,
        join: d in "depth_cte",
        on: fragment("(? ->> 'parent_job_id')::bigint", s.results) == d.id,
        select: %{id: s.id, depth: d.depth + 1}
      )

    cte_query =
      initial_query
      |> union_all(^recursive_query)

    result =
      from(d in subquery({"depth_cte", cte_query}),
        select: max(d.depth)
      )
      |> Repo.one()

    result || 0
  end
end
