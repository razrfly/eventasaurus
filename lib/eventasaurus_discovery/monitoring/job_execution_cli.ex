defmodule EventasaurusDiscovery.Monitoring.JobExecutionCLI do
  @moduledoc """
  CLI utilities for monitoring job executions from the command line.

  Provides formatted output for:
  - Recent job executions with filtering
  - Job statistics (success rate, avg duration)
  - Failure analysis
  - Source-specific metrics
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  @doc """
  List recent job executions with optional filtering.

  ## Options
    * `:limit` - Number of executions to show (default: 50)
    * `:state` - Filter by state (:success, :failure, :cancelled, :discarded)
    * `:worker` - Filter by worker name (substring match)
    * `:source` - Filter by source name (e.g., "week_pl")

  ## Examples

      iex> list_executions()
      iex> list_executions(limit: 20, state: :failure)
      iex> list_executions(source: "week_pl")
  """
  def list_executions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    state = Keyword.get(opts, :state)
    worker = Keyword.get(opts, :worker)
    source = Keyword.get(opts, :source)

    query =
      from(j in JobExecutionSummary,
        order_by: [desc: j.inserted_at],
        limit: ^limit
      )

    query = apply_filters(query, state, worker, source)

    executions = Repo.replica().all(query)

    print_executions_table(executions)
    print_summary(executions)

    {:ok, length(executions)}
  end

  @doc """
  Show job execution statistics.

  ## Options
    * `:source` - Filter by source name
    * `:worker` - Filter by worker name
    * `:hours` - Time range in hours (default: 24)

  ## Examples

      iex> show_stats()
      iex> show_stats(source: "week_pl")
      iex> show_stats(hours: 168)  # Last week
  """
  def show_stats(opts \\ []) do
    source = Keyword.get(opts, :source)
    worker = Keyword.get(opts, :worker)
    hours = Keyword.get(opts, :hours, 24)

    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -hours * 3600)

    query =
      from(j in JobExecutionSummary,
        where: j.inserted_at >= ^cutoff
      )

    query = apply_filters(query, nil, worker, source)

    executions = Repo.replica().all(query)

    print_statistics(executions, hours)

    {:ok, length(executions)}
  end

  @doc """
  Show recent failures with error details.

  ## Options
    * `:limit` - Number of failures to show (default: 20)
    * `:source` - Filter by source name

  ## Examples

      iex> show_failures()
      iex> show_failures(limit: 10, source: "week_pl")
  """
  def show_failures(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    source = Keyword.get(opts, :source)

    query =
      from(j in JobExecutionSummary,
        where: j.state == "failure",
        order_by: [desc: j.inserted_at],
        limit: ^limit
      )

    # Use apply_filters for consistent filtering with proper PascalCase conversion
    query = apply_filters(query, nil, nil, source)

    failures = Repo.replica().all(query)

    print_failures_table(failures)

    {:ok, length(failures)}
  end

  # Private Functions

  defp apply_filters(query, state, worker, source) do
    query
    |> filter_by_state(state)
    |> filter_by_worker(worker)
    |> filter_by_source(source)
  end

  defp filter_by_state(query, nil), do: query

  defp filter_by_state(query, state) when state in [:success, :failure, :cancelled, :discarded] do
    state_string = Atom.to_string(state)
    from(j in query, where: j.state == ^state_string)
  end

  defp filter_by_worker(query, nil), do: query

  defp filter_by_worker(query, worker) do
    # Use simple LIKE without ESCAPE clause since we're controlling the pattern
    from(j in query, where: like(j.worker, ^"%#{worker}%"))
  end

  defp filter_by_source(query, nil), do: query

  defp filter_by_source(query, source) do
    # Source name appears in worker like: EventasaurusDiscovery.Sources.WeekPl.Jobs.SyncJob
    # Convert snake_case to PascalCase for matching
    pascal_source = Macro.camelize(source)
    from(j in query, where: like(j.worker, ^"%#{pascal_source}%"))
  end

  # Formatting Functions

  defp print_executions_table(executions) do
    IO.puts("\n" <> IO.ANSI.bright() <> "Recent Job Executions:" <> IO.ANSI.reset())
    IO.puts(String.duplicate("━", 120))

    IO.puts(
      format_row([
        pad("Source", 20),
        pad("Worker", 20),
        pad("State", 10),
        pad("Duration", 10),
        pad("Started At", 20)
      ])
    )

    IO.puts(String.duplicate("━", 120))

    Enum.each(executions, fn exec ->
      source = extract_source(exec.worker)
      job_name = extract_job_name(exec.worker)
      state_colored = colorize_state(exec.state)
      duration = format_duration(exec.duration_ms)
      started = format_datetime(exec.attempted_at)

      IO.puts(
        format_row([
          pad(source, 20),
          pad(job_name, 20),
          pad(state_colored, 10),
          pad(duration, 10),
          pad(started, 20)
        ])
      )
    end)

    IO.puts(String.duplicate("━", 120) <> "\n")
  end

  defp print_failures_table(failures) do
    IO.puts("\n" <> IO.ANSI.red() <> IO.ANSI.bright() <> "Recent Failures:" <> IO.ANSI.reset())
    IO.puts(String.duplicate("━", 120))

    Enum.each(failures, fn failure ->
      source = extract_source(failure.worker)
      job_name = extract_job_name(failure.worker)
      started = format_datetime(failure.attempted_at)
      error = String.slice(failure.error || "Unknown error", 0, 80)

      IO.puts("\n#{IO.ANSI.yellow()}┌ #{source} → #{job_name}#{IO.ANSI.reset()}")
      IO.puts("├ #{IO.ANSI.cyan()}Started:#{IO.ANSI.reset()} #{started}")

      IO.puts(
        "├ #{IO.ANSI.cyan()}Duration:#{IO.ANSI.reset()} #{format_duration(failure.duration_ms)}"
      )

      IO.puts("└ #{IO.ANSI.red()}Error:#{IO.ANSI.reset()} #{error}")
    end)

    IO.puts("\n" <> String.duplicate("━", 120) <> "\n")
  end

  defp print_summary(executions) do
    total = length(executions)
    successes = Enum.count(executions, &(&1.state == :success))
    failures = Enum.count(executions, &(&1.state == :failure))
    success_rate = if total > 0, do: Float.round(successes / total * 100, 1), else: 0.0

    avg_duration =
      executions
      |> Enum.map(& &1.duration_ms)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> 0
        durations -> Enum.sum(durations) / length(durations)
      end

    IO.puts("#{IO.ANSI.cyan()}Summary:#{IO.ANSI.reset()}")
    IO.puts("  Total: #{total}")
    IO.puts("  Success: #{IO.ANSI.green()}#{successes}#{IO.ANSI.reset()}")
    IO.puts("  Failures: #{IO.ANSI.red()}#{failures}#{IO.ANSI.reset()}")
    IO.puts("  Success Rate: #{success_rate}%")
    IO.puts("  Avg Duration: #{format_duration(round(avg_duration))}")
    IO.puts("")
  end

  defp print_statistics(executions, hours) do
    total = length(executions)
    successes = Enum.count(executions, &(&1.state == :success))
    failures = Enum.count(executions, &(&1.state == :failure))
    success_rate = if total > 0, do: Float.round(successes / total * 100, 1), else: 0.0

    avg_duration =
      executions
      |> Enum.map(& &1.duration_ms)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> 0
        durations -> Enum.sum(durations) / length(durations)
      end

    # Group by source
    by_source =
      executions
      |> Enum.group_by(&extract_source(&1.worker))
      |> Enum.map(fn {source, execs} ->
        source_successes = Enum.count(execs, &(&1.state == :success))
        source_total = length(execs)

        source_rate =
          if source_total > 0,
            do: Float.round(source_successes / source_total * 100, 1),
            else: 0.0

        {source, source_total, source_successes, source_rate}
      end)
      |> Enum.sort_by(fn {_, total, _, _} -> total end, :desc)

    IO.puts(
      "\n" <>
        IO.ANSI.bright() <> "Job Execution Statistics (Last #{hours} hours):" <> IO.ANSI.reset()
    )

    IO.puts(String.duplicate("━", 80))
    IO.puts("\n#{IO.ANSI.cyan()}Overall:#{IO.ANSI.reset()}")
    IO.puts("  Total Executions: #{total}")
    IO.puts("  Successes: #{IO.ANSI.green()}#{successes}#{IO.ANSI.reset()}")
    IO.puts("  Failures: #{IO.ANSI.red()}#{failures}#{IO.ANSI.reset()}")
    IO.puts("  Success Rate: #{success_rate}%")
    IO.puts("  Avg Duration: #{format_duration(round(avg_duration))}")

    IO.puts("\n#{IO.ANSI.cyan()}By Source:#{IO.ANSI.reset()}")
    IO.puts(String.duplicate("─", 80))

    IO.puts(
      format_row([
        pad("Source", 25),
        pad("Total", 10),
        pad("Success", 10),
        pad("Rate", 10)
      ])
    )

    IO.puts(String.duplicate("─", 80))

    Enum.each(by_source, fn {source, total, successes, rate} ->
      IO.puts(
        format_row([
          pad(source, 25),
          pad("#{total}", 10),
          pad("#{successes}", 10),
          pad("#{rate}%", 10)
        ])
      )
    end)

    IO.puts(String.duplicate("━", 80) <> "\n")
  end

  # Helper Functions

  defp extract_source(worker) do
    worker
    |> String.split(".")
    |> Enum.at(-3)
    |> case do
      nil -> "unknown"
      source -> Macro.underscore(source)
    end
  end

  defp extract_job_name(worker) do
    worker
    |> String.split(".")
    |> List.last() ||
      "Unknown"
  end

  defp format_duration(nil), do: "N/A"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 2)}s"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  defp colorize_state(:success), do: IO.ANSI.green() <> "success" <> IO.ANSI.reset()
  defp colorize_state(:failure), do: IO.ANSI.red() <> "failure" <> IO.ANSI.reset()
  defp colorize_state(:cancelled), do: IO.ANSI.yellow() <> "cancelled" <> IO.ANSI.reset()
  defp colorize_state(:discarded), do: IO.ANSI.magenta() <> "discarded" <> IO.ANSI.reset()
  defp colorize_state(other), do: "#{other}"

  defp pad(string, width) do
    String.pad_trailing(string, width)
  end

  defp format_row(columns) do
    Enum.join(columns, " ")
  end
end
