defmodule EventasaurusDiscovery.Monitoring.Chain do
  @moduledoc """
  Programmatic API for analyzing job execution chains and cascade failures.

  Shows parent-child job relationships and how failures propagate through
  the execution chain. Useful for multi-step scrapers like Cinema City
  and Repertuary.

  ## Examples

      # Analyze chain for a specific job
      {:ok, chain} = Chain.analyze_job(12345)

      # Find recent chains for a source
      {:ok, chains} = Chain.recent_chains("cinema_city", limit: 5)

      # Calculate chain statistics
      stats = Chain.statistics(chain)

      # Find cascade failures
      cascades = Chain.cascade_failures(chain)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusDiscovery.JobExecutionSummaries.Lineage
  import Ecto.Query

  # Legacy patterns - patterns are now generated dynamically in get_sync_worker/1

  @doc """
  Analyzes the execution chain for a specific job ID.

  Returns a tree structure representing the job and all its descendants.

  ## Examples

      {:ok, chain} = Chain.analyze_job(12345)
      {:error, :not_found} = Chain.analyze_job(99999)
  """
  def analyze_job(job_id) do
    case Repo.replica().get(JobExecutionSummary, job_id) do
      nil ->
        {:error, :not_found}

      job ->
        tree = build_tree_node(job)
        {:ok, tree}
    end
  end

  @doc """
  Returns recent execution chains for a source.

  ## Options

    * `:limit` - Maximum number of chains to return (default: 5)
    * `:failed_only` - Only return chains with failures (default: false)

  ## Examples

      {:ok, chains} = Chain.recent_chains("cinema_city", limit: 3)
      {:ok, failed_chains} = Chain.recent_chains("cinema_city", failed_only: true)
  """
  def recent_chains(source, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    failed_only = Keyword.get(opts, :failed_only, false)

    case get_sync_worker(source) do
      {:ok, sync_worker} ->
        query =
          from(j in JobExecutionSummary,
            where: j.worker == ^sync_worker,
            order_by: [desc: j.attempted_at],
            limit: ^limit
          )

        query =
          if failed_only do
            from(j in query, where: j.state in ["discarded", "cancelled"])
          else
            query
          end

        sync_jobs = Repo.replica().all(query)

        chains = Enum.map(sync_jobs, &build_tree_node/1)
        {:ok, chains}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Calculates statistics for a chain.

  Returns:
    * `:total` - Total number of jobs in chain
    * `:completed` - Number of completed jobs
    * `:failed` - Number of failed jobs
    * `:success_rate` - Overall success rate
    * `:cascade_failures` - List of cascade failures

  ## Examples

      {:ok, chain} = Chain.analyze_job(12345)
      stats = Chain.statistics(chain)
      # => %{total: 10, completed: 8, failed: 2, success_rate: 80.0, ...}
  """
  def statistics(chain) do
    all_nodes = flatten_tree(chain)

    total = length(all_nodes)
    completed = Enum.count(all_nodes, &(&1.state == "completed"))
    failed = Enum.count(all_nodes, &(&1.state in ["discarded", "cancelled"]))

    # Find cascade failures
    cascade_failures =
      all_nodes
      |> Enum.filter(&(&1.state in ["discarded", "cancelled"]))
      |> Enum.flat_map(fn failed_node ->
        prevented_count = count_descendants(failed_node)

        if prevented_count > 0 do
          [
            %{
              job_id: failed_node.job_id,
              worker: failed_node.worker |> String.split(".") |> List.last(),
              error_category: failed_node.results["error_category"],
              prevented_count: prevented_count
            }
          ]
        else
          []
        end
      end)

    success_rate = if total > 0, do: completed / total * 100, else: 0

    %{
      total: total,
      completed: completed,
      failed: failed,
      success_rate: success_rate,
      cascade_failures: cascade_failures
    }
  end

  @doc """
  Returns cascade failures from a chain.

  A cascade failure occurs when a parent job fails and prevents
  child jobs from executing.

  ## Examples

      {:ok, chain} = Chain.analyze_job(12345)
      cascades = Chain.cascade_failures(chain)
      # => [%{job_id: 123, worker: "MovieDetailJob", prevented_count: 5}, ...]
  """
  def cascade_failures(chain) do
    stats = statistics(chain)
    stats.cascade_failures
  end

  @doc """
  Returns the total impact of cascade failures.

  Returns the total number of jobs prevented from executing
  due to cascade failures.

  ## Examples

      {:ok, chain} = Chain.analyze_job(12345)
      impact = Chain.cascade_impact(chain)
      # => 15
  """
  def cascade_impact(chain) do
    chain
    |> cascade_failures()
    |> Enum.map(& &1.prevented_count)
    |> Enum.sum()
  end

  # Private helpers

  # Dynamically generate SyncJob worker name from source name
  # e.g., "cinema_city" -> "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob"
  defp get_sync_worker(source) when is_binary(source) do
    module_name =
      source
      |> String.split("_")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")

    worker = "EventasaurusDiscovery.Sources.#{module_name}.Jobs.SyncJob"
    {:ok, worker}
  end

  defp get_sync_worker(_), do: {:error, :invalid_source}

  defp build_tree_node(job) do
    # Get all descendants
    descendants = Lineage.get_descendants(job.id)

    # Build map of job_id -> job for quick lookup
    jobs_by_id = Map.new(descendants, &{&1.id, &1})

    # Find direct children
    children =
      descendants
      |> Enum.filter(fn child ->
        get_in(child.results, ["parent_job_id"]) == job.id
      end)
      |> Enum.map(&build_tree_node_recursive(&1, jobs_by_id))

    %{
      job_id: job.id,
      worker: job.worker,
      state: job.state,
      attempted_at: job.attempted_at,
      results: job.results,
      children: children
    }
  end

  defp build_tree_node_recursive(job, jobs_by_id) do
    # Find direct children
    children =
      jobs_by_id
      |> Enum.filter(fn {_id, child} ->
        get_in(child.results, ["parent_job_id"]) == job.id
      end)
      |> Enum.map(fn {_id, child} -> build_tree_node_recursive(child, jobs_by_id) end)

    %{
      job_id: job.id,
      worker: job.worker,
      state: job.state,
      attempted_at: job.attempted_at,
      results: job.results,
      children: children
    }
  end

  defp flatten_tree(node) do
    [node | Enum.flat_map(node.children, &flatten_tree/1)]
  end

  defp count_descendants(node) do
    direct_children = length(node.children)

    grandchildren_count =
      node.children
      |> Enum.map(&count_descendants/1)
      |> Enum.sum()

    direct_children + grandchildren_count
  end
end
