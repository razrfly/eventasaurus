defmodule Mix.Tasks.Monitor.Chain do
  @moduledoc """
  Visualizes job execution chains and cascade failures.

  Shows parent-child job relationships and how failures propagate through
  the execution chain. Useful for multi-step scrapers like Cinema City
  and Repertuary.

  ## Usage

      # Visualize chain for recent Cinema City sync
      mix monitor.chain --source cinema_city

      # Show chain for specific job ID
      mix monitor.chain --job-id 12345

      # Show only failed chains
      mix monitor.chain --source cinema_city --failed-only

      # Limit depth of chain visualization
      mix monitor.chain --source cinema_city --depth 2

  ## Output Example

      🔗 Cinema City Job Execution Chain
      ================================================================

      SyncJob #45123 (completed) - 2024-11-23 12:00:00
      ├─ CinemaDateJob #45124 (completed) - 12:00:05
      │  ├─ MovieDetailJob #45125 (completed) - 12:00:12
      │  │  └─ ShowtimeProcessJob #45130 (completed) - 12:00:18
      │  ├─ MovieDetailJob #45126 (failed: network_error) - 12:00:15
      │  │  └─ [cascade] ShowtimeProcessJob #45131 (skipped)
      │  └─ MovieDetailJob #45127 (completed) - 12:00:20
      │     └─ ShowtimeProcessJob #45132 (completed) - 12:00:25
      └─ CinemaDateJob #45128 (failed: validation_error) - 12:00:08
         └─ [cascade] All child jobs skipped

      Chain Statistics:
      ├─ Total Jobs: 9
      ├─ Completed: 6 (66.7%)
      ├─ Failed: 2 (22.2%)
      ├─ Cascaded Failures: 2 (22.2%)
      └─ Chain Success Rate: 66.7%

      Cascade Analysis:
      ├─ MovieDetailJob #45126 network_error → 1 child skipped
      └─ CinemaDateJob #45128 validation_error → all children skipped

      💡 Impact:
      - 2 cascade failures prevented 2 downstream jobs from executing
      - Root cause: Fix network_error and validation_error to prevent cascade
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusDiscovery.JobExecutionSummaries.Lineage
  alias EventasaurusDiscovery.Sources.SourcePatterns
  import Ecto.Query

  @shortdoc "Visualizes job execution chains and cascade failures"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          source: :string,
          job_id: :integer,
          failed_only: :boolean,
          depth: :integer,
          limit: :integer
        ],
        aliases: [s: :source, j: :job_id, f: :failed_only, d: :depth, l: :limit]
      )

    cond do
      opts[:job_id] ->
        display_chain_for_job(opts[:job_id], opts[:depth])

      opts[:source] ->
        display_chains_for_source(
          opts[:source],
          opts[:failed_only] || false,
          opts[:depth],
          opts[:limit] || 5
        )

      true ->
        IO.puts(IO.ANSI.red() <> "❌ Error: --source or --job-id required" <> IO.ANSI.reset())
        SourcePatterns.print_available_sources()
        System.halt(1)
    end
  end

  defp display_chain_for_job(job_id, max_depth) do
    case Repo.get(JobExecutionSummary, job_id) do
      nil ->
        IO.puts(IO.ANSI.red() <> "❌ Job ##{job_id} not found" <> IO.ANSI.reset())
        System.halt(1)

      job ->
        source = extract_source_from_worker(job.worker)

        IO.puts("\n" <> IO.ANSI.cyan() <> "🔗 #{source} Job Execution Chain" <> IO.ANSI.reset())
        IO.puts(String.duplicate("=", 64))
        IO.puts("")

        # Build nested tree
        tree = build_tree_node(job)
        display_tree(tree, 0, max_depth)

        # Calculate statistics
        stats = calculate_chain_stats(tree)
        display_chain_stats(stats)
    end
  end

  defp display_chains_for_source(source, failed_only, max_depth, limit) do
    unless SourcePatterns.valid_source?(source) do
      IO.puts(IO.ANSI.red() <> "❌ Error: Unknown source '#{source}'" <> IO.ANSI.reset())
      SourcePatterns.print_available_sources()
      System.halt(1)
    end

    {:ok, sync_worker} = SourcePatterns.get_sync_worker(source)

    # Get recent sync jobs
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

    sync_jobs = Repo.all(query)

    if Enum.empty?(sync_jobs) do
      IO.puts(
        IO.ANSI.yellow() <>
          "⚠️  No sync jobs found for #{source}" <> IO.ANSI.reset()
      )

      System.halt(0)
    end

    source_display = SourcePatterns.get_display_name(source)

    IO.puts(
      "\n" <> IO.ANSI.cyan() <> "🔗 #{source_display} Job Execution Chains" <> IO.ANSI.reset()
    )

    IO.puts(String.duplicate("=", 64))
    IO.puts("Showing #{length(sync_jobs)} most recent sync jobs")
    IO.puts("")

    # Display each chain
    sync_jobs
    |> Enum.each(fn job ->
      tree = build_tree_node(job)
      display_tree(tree, 0, max_depth)
      IO.puts("")

      stats = calculate_chain_stats(tree)
      display_chain_stats(stats)
      IO.puts("")
      IO.puts(String.duplicate("-", 64))
      IO.puts("")
    end)
  end

  defp build_tree_node(job) do
    # Get all descendants
    descendants = Lineage.get_descendants(job.id)

    # Build map of job_id -> job for quick lookup
    jobs_by_id = Map.new(descendants, &{&1.id, &1})

    # Find direct children (jobs whose parent_job_id is this job's id)
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
    # Find direct children of this job from the jobs_by_id map
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

  defp display_tree(node, depth, max_depth) do
    if max_depth && depth >= max_depth do
      indent = String.duplicate("│  ", depth)
      IO.puts("#{indent}└─ [#{length(node.children)} more jobs truncated...]")
    else
      # Display current node
      indent = String.duplicate("│  ", depth)

      prefix =
        cond do
          depth == 0 -> ""
          length(node.children) > 0 -> "├─ "
          true -> "└─ "
        end

      job_name = node.worker |> String.split(".") |> List.last()
      state_display = format_state(node.state, node.results["error_category"])
      time_display = format_time(node.attempted_at)

      IO.puts("#{indent}#{prefix}#{job_name} ##{node.job_id} #{state_display} - #{time_display}")

      # Display children
      if length(node.children) > 0 do
        node.children
        |> Enum.with_index()
        |> Enum.each(fn {child, index} ->
          is_last = index == length(node.children) - 1

          if is_last do
            # Last child - change prefix
            display_tree(child, depth + 1, max_depth)
          else
            display_tree(child, depth + 1, max_depth)
          end
        end)
      end
    end
  end

  defp calculate_chain_stats(tree) do
    # Flatten tree to get all nodes
    all_nodes = flatten_tree(tree)

    total = length(all_nodes)
    completed = Enum.count(all_nodes, &(&1.state == "completed"))
    failed = Enum.count(all_nodes, &(&1.state in ["discarded", "cancelled"]))

    # Find cascade failures (parent failed, children didn't execute or were skipped)
    cascade_failures =
      all_nodes
      |> Enum.filter(&(&1.state in ["discarded", "cancelled"]))
      |> Enum.flat_map(fn failed_node ->
        # Count how many children this failure prevented
        prevented_count = count_descendants(failed_node)

        if prevented_count > 0 do
          [
            %{
              job_id: failed_node.job_id,
              worker: failed_node.worker,
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

  defp flatten_tree(node) do
    [node | Enum.flat_map(node.children, &flatten_tree/1)]
  end

  defp count_descendants(node) do
    # Count all descendants (children, grandchildren, etc.)
    direct_children = length(node.children)

    grandchildren_count =
      node.children
      |> Enum.map(&count_descendants/1)
      |> Enum.sum()

    direct_children + grandchildren_count
  end

  defp display_chain_stats(stats) do
    IO.puts(IO.ANSI.green() <> "Chain Statistics:" <> IO.ANSI.reset())
    IO.puts("├─ Total Jobs: #{stats.total}")

    IO.puts(
      "├─ Completed: #{stats.completed} (#{format_percent(stats.completed / stats.total * 100)})"
    )

    IO.puts("├─ Failed: #{stats.failed} (#{format_percent(stats.failed / stats.total * 100)})")

    cascade_count = length(stats.cascade_failures)

    IO.puts(
      "├─ Cascaded Failures: #{cascade_count} (#{format_percent(cascade_count / stats.total * 100)})"
    )

    IO.puts("└─ Chain Success Rate: #{format_percent(stats.success_rate)}")

    if length(stats.cascade_failures) > 0 do
      IO.puts("")
      IO.puts(IO.ANSI.yellow() <> "Cascade Analysis:" <> IO.ANSI.reset())

      stats.cascade_failures
      |> Enum.with_index()
      |> Enum.each(fn {cascade, index} ->
        prefix = if index == length(stats.cascade_failures) - 1, do: "└─", else: "├─"
        job_name = cascade.worker |> String.split(".") |> List.last()
        error = cascade.error_category || "unknown error"

        children_text =
          if cascade.prevented_count == 1 do
            "1 child skipped"
          else
            "#{cascade.prevented_count} children skipped"
          end

        IO.puts("#{prefix} #{job_name} ##{cascade.job_id} #{error} → #{children_text}")
      end)

      IO.puts("")
      IO.puts(IO.ANSI.magenta() <> "💡 Impact:" <> IO.ANSI.reset())

      total_prevented =
        stats.cascade_failures
        |> Enum.map(& &1.prevented_count)
        |> Enum.sum()

      IO.puts(
        "- #{cascade_count} cascade failures prevented #{total_prevented} downstream jobs from executing"
      )

      # Group by error category for root cause
      error_categories =
        stats.cascade_failures
        |> Enum.map(& &1.error_category)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      if length(error_categories) > 0 do
        error_list = Enum.join(error_categories, " and ")
        IO.puts("- Root cause: Fix #{error_list} to prevent cascade")
      end
    end
  end

  defp format_state(state, error_category) do
    case state do
      "completed" ->
        IO.ANSI.green() <> "(completed)" <> IO.ANSI.reset()

      "discarded" ->
        error_text = if error_category, do: ": #{error_category}", else: ""
        IO.ANSI.red() <> "(failed#{error_text})" <> IO.ANSI.reset()

      "cancelled" ->
        IO.ANSI.yellow() <> "(cancelled)" <> IO.ANSI.reset()

      _ ->
        "(#{state})"
    end
  end

  defp format_time(dt) when is_struct(dt, DateTime) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "N/A"

  defp format_percent(value) do
    "#{Float.round(value, 1)}%"
  end

  defp extract_source_from_worker(worker) do
    worker
    |> String.split(".")
    |> Enum.at(2)
    |> case do
      nil -> "Unknown"
      name -> name
    end
  end
end
