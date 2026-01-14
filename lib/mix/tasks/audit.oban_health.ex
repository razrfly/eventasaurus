defmodule Mix.Tasks.Audit.ObanHealth do
  @moduledoc """
  Audit Oban queue health and detect corrupted jobs.

  Checks for:
  - Zombie available jobs (exhausted attempts but still in 'available' state)
  - Priority 0 blockers (stuck jobs blocking queues)
  - Stuck executing jobs (older than Lifeline's rescue_after)
  - Queue concurrency and pending job counts

  ## Usage

      # Run full health check
      mix audit.oban_health

      # Only show problems (skip healthy queues)
      mix audit.oban_health --problems-only

      # Fix detected issues (runs the sanitizer worker)
      mix audit.oban_health --fix

      # Retry a specific job by ID
      mix audit.oban_health --retry 12345

      # Cancel a specific job by ID
      mix audit.oban_health --cancel 12345

  ## Related

  The ObanJobSanitizerWorker runs every 30 minutes to automatically fix issues.
  This CLI task is for manual inspection and on-demand fixes.

  See: lib/eventasaurus_app/workers/oban_job_sanitizer_worker.ex
  """

  use Mix.Task
  require Logger

  import Ecto.Query

  @shortdoc "Audit Oban queue health and detect corrupted jobs"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [problems_only: :boolean, fix: :boolean, retry: :integer, cancel: :integer],
        aliases: [p: :problems_only, f: :fix, r: :retry, c: :cancel]
      )

    problems_only = opts[:problems_only] || false
    fix_issues = opts[:fix] || false
    retry_job_id = opts[:retry]
    cancel_job_id = opts[:cancel]

    repo = EventasaurusApp.ObanRepo

    # Handle single job operations first
    cond do
      retry_job_id ->
        handle_retry_job(repo, retry_job_id)
        System.halt(0)

      cancel_job_id ->
        handle_cancel_job(repo, cancel_job_id)
        System.halt(0)

      true ->
        :continue
    end

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "🏥 Oban Health Report" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 70) <> IO.ANSI.reset())
    IO.puts("")

    # Get detection results from the worker
    detection = EventasaurusApp.Workers.ObanJobSanitizerWorker.detect_all()

    # Display corrupted jobs
    display_corrupted_jobs(detection, problems_only)

    # Display queue status
    display_queue_status(repo, problems_only)

    # Display summary
    total_issues =
      length(detection.zombie_available) +
        length(detection.priority_zero_blockers) +
        length(detection.stuck_executing)

    IO.puts(IO.ANSI.cyan() <> String.duplicate("━", 70) <> IO.ANSI.reset())

    if total_issues == 0 do
      IO.puts(IO.ANSI.green() <> "✅ Oban queues are healthy - no issues detected" <> IO.ANSI.reset())
    else
      IO.puts(
        IO.ANSI.yellow() <>
          "⚠️  #{total_issues} corrupted job(s) detected" <>
          IO.ANSI.reset()
      )

      if fix_issues do
        IO.puts("")
        IO.puts("🔧 Running sanitizer to fix issues...")

        case EventasaurusApp.Workers.ObanJobSanitizerWorker.new(%{}) |> Oban.insert() do
          {:ok, job} ->
            IO.puts(
              IO.ANSI.green() <>
                "✅ Sanitizer job enqueued (job ID: #{job.id})" <>
                IO.ANSI.reset()
            )

            IO.puts("   Check results: mix monitor.jobs list --limit 5")

          {:error, reason} ->
            IO.puts(
              IO.ANSI.red() <>
                "❌ Failed to enqueue sanitizer: #{inspect(reason)}" <>
                IO.ANSI.reset()
            )
        end
      else
        IO.puts("")
        IO.puts(IO.ANSI.blue() <> "💡 To fix these issues, run:" <> IO.ANSI.reset())
        IO.puts("   mix audit.oban_health --fix")
      end
    end

    IO.puts("")
  end

  defp display_corrupted_jobs(detection, problems_only) do
    # Zombie available jobs
    zombies = detection.zombie_available

    if length(zombies) > 0 do
      IO.puts(IO.ANSI.red() <> "🧟 Zombie Available Jobs (#{length(zombies)})" <> IO.ANSI.reset())
      IO.puts("   Jobs with exhausted attempts stuck in 'available' state:")
      IO.puts("")
      IO.puts("   #{pad("ID", 10)} #{pad("Queue", 20)} #{pad("Worker", 40)} Attempt")
      IO.puts("   #{String.duplicate("─", 80)}")

      Enum.each(zombies, fn job ->
        worker_short = String.split(job.worker, ".") |> List.last()

        IO.puts(
          "   #{pad(to_string(job.id), 10)} #{pad(job.queue, 20)} #{pad(worker_short, 40)} #{job.attempt}"
        )
      end)

      IO.puts("")
    else
      unless problems_only do
        IO.puts(IO.ANSI.green() <> "✅ No zombie available jobs" <> IO.ANSI.reset())
      end
    end

    # Priority zero blockers
    blockers = detection.priority_zero_blockers

    if length(blockers) > 0 do
      IO.puts(
        IO.ANSI.yellow() <>
          "🚧 Priority 0 Blockers (#{length(blockers)})" <>
          IO.ANSI.reset()
      )

      IO.puts("   High-priority jobs that may be blocking queues:")
      IO.puts("")
      IO.puts("   #{pad("ID", 10)} #{pad("Queue", 20)} #{pad("Worker", 40)} Attempt")
      IO.puts("   #{String.duplicate("─", 80)}")

      Enum.each(blockers, fn job ->
        worker_short = String.split(job.worker, ".") |> List.last()

        IO.puts(
          "   #{pad(to_string(job.id), 10)} #{pad(job.queue, 20)} #{pad(worker_short, 40)} #{job.attempt}"
        )
      end)

      IO.puts("")
    else
      unless problems_only do
        IO.puts(IO.ANSI.green() <> "✅ No priority 0 blockers" <> IO.ANSI.reset())
      end
    end

    # Stuck executing jobs
    stuck = detection.stuck_executing

    if length(stuck) > 0 do
      IO.puts(
        IO.ANSI.yellow() <>
          "⏳ Stuck Executing Jobs (#{length(stuck)})" <>
          IO.ANSI.reset()
      )

      IO.puts("   Jobs executing longer than Lifeline's 5-minute rescue_after:")
      IO.puts("")
      IO.puts("   #{pad("ID", 10)} #{pad("Queue", 20)} #{pad("Worker", 30)} Attempted At")
      IO.puts("   #{String.duplicate("─", 80)}")

      Enum.each(stuck, fn job ->
        worker_short = String.split(job.worker, ".") |> List.last()
        attempted = format_datetime(job.attempted_at)

        IO.puts(
          "   #{pad(to_string(job.id), 10)} #{pad(job.queue, 20)} #{pad(worker_short, 30)} #{attempted}"
        )
      end)

      IO.puts("")
      IO.puts("   Note: Lifeline plugin should rescue these automatically")
      IO.puts("")
    else
      unless problems_only do
        IO.puts(IO.ANSI.green() <> "✅ No stuck executing jobs" <> IO.ANSI.reset())
      end
    end
  end

  defp display_queue_status(repo, problems_only) do
    IO.puts(IO.ANSI.blue() <> "📊 Queue Status" <> IO.ANSI.reset())
    IO.puts("")

    # Get queue statistics
    stats = get_queue_stats(repo)

    if Enum.empty?(stats) do
      IO.puts("   No jobs in queues")
    else
      IO.puts(
        "   #{pad("Queue", 20)} #{pad("Available", 12)} #{pad("Executing", 12)} #{pad("Scheduled", 12)} #{pad("Retryable", 12)}"
      )

      IO.puts("   #{String.duplicate("─", 70)}")

      Enum.each(stats, fn {queue, counts} ->
        available = counts[:available] || 0
        executing = counts[:executing] || 0
        scheduled = counts[:scheduled] || 0
        retryable = counts[:retryable] || 0

        # Highlight queues with issues
        color =
          cond do
            available > 100 -> IO.ANSI.yellow()
            executing > 10 -> IO.ANSI.yellow()
            retryable > 50 -> IO.ANSI.yellow()
            true -> ""
          end

        reset = if color != "", do: IO.ANSI.reset(), else: ""

        unless problems_only && color == "" do
          IO.puts(
            "   #{color}#{pad(queue, 20)} #{pad(to_string(available), 12)} #{pad(to_string(executing), 12)} #{pad(to_string(scheduled), 12)} #{pad(to_string(retryable), 12)}#{reset}"
          )
        end
      end)
    end

    IO.puts("")
  end

  defp get_queue_stats(repo) do
    query =
      from(j in "oban_jobs",
        where: j.state in ["available", "executing", "scheduled", "retryable"],
        group_by: [j.queue, j.state],
        select: {j.queue, j.state, count(j.id)}
      )

    repo.all(query)
    |> Enum.group_by(fn {queue, _state, _count} -> queue end)
    |> Enum.map(fn {queue, rows} ->
      counts =
        Enum.reduce(rows, %{}, fn {_q, state, count}, acc ->
          Map.put(acc, String.to_atom(state), count)
        end)

      {queue, counts}
    end)
    |> Enum.sort_by(fn {queue, _} -> queue end)
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp pad(str, width) do
    str
    |> to_string()
    |> String.pad_trailing(width)
  end

  # Single job operations

  defp handle_retry_job(repo, job_id) do
    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "🔄 Retrying Job ##{job_id}" <> IO.ANSI.reset())
    IO.puts("")

    case get_job(repo, job_id) do
      nil ->
        IO.puts(IO.ANSI.red() <> "❌ Job ##{job_id} not found" <> IO.ANSI.reset())

      job ->
        display_job_details(job)

        case Oban.retry_job(job_id) do
          :ok ->
            IO.puts(IO.ANSI.green() <> "✅ Job ##{job_id} queued for retry" <> IO.ANSI.reset())

          {:ok, _} ->
            IO.puts(IO.ANSI.green() <> "✅ Job ##{job_id} queued for retry" <> IO.ANSI.reset())

          {:error, reason} ->
            IO.puts(
              IO.ANSI.red() <>
                "❌ Failed to retry job: #{inspect(reason)}" <>
                IO.ANSI.reset()
            )
        end
    end
  end

  defp handle_cancel_job(repo, job_id) do
    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "🚫 Cancelling Job ##{job_id}" <> IO.ANSI.reset())
    IO.puts("")

    case get_job(repo, job_id) do
      nil ->
        IO.puts(IO.ANSI.red() <> "❌ Job ##{job_id} not found" <> IO.ANSI.reset())

      job ->
        display_job_details(job)

        case Oban.cancel_job(job_id) do
          :ok ->
            IO.puts(IO.ANSI.green() <> "✅ Job ##{job_id} cancelled" <> IO.ANSI.reset())

          {:ok, _} ->
            IO.puts(IO.ANSI.green() <> "✅ Job ##{job_id} cancelled" <> IO.ANSI.reset())

          {:error, reason} ->
            IO.puts(
              IO.ANSI.red() <>
                "❌ Failed to cancel job: #{inspect(reason)}" <>
                IO.ANSI.reset()
            )
        end
    end
  end

  defp get_job(repo, job_id) do
    query =
      from(j in "oban_jobs",
        where: j.id == ^job_id,
        select: %{
          id: j.id,
          queue: j.queue,
          worker: j.worker,
          state: j.state,
          attempt: j.attempt,
          max_attempts: j.max_attempts,
          scheduled_at: j.scheduled_at,
          attempted_at: j.attempted_at,
          errors: j.errors
        }
      )

    repo.one(query)
  end

  defp display_job_details(job) do
    worker_short = String.split(job.worker, ".") |> List.last()

    IO.puts("   ID:          #{job.id}")
    IO.puts("   Worker:      #{worker_short}")
    IO.puts("   Queue:       #{job.queue}")
    IO.puts("   State:       #{job.state}")
    IO.puts("   Attempt:     #{job.attempt}/#{job.max_attempts}")
    IO.puts("   Scheduled:   #{format_datetime(job.scheduled_at)}")
    IO.puts("   Attempted:   #{format_datetime(job.attempted_at)}")

    if job.errors && length(job.errors) > 0 do
      latest_error = List.first(job.errors)

      if is_map(latest_error) do
        error_msg = latest_error["message"] || latest_error["error"] || inspect(latest_error)
        truncated = String.slice(to_string(error_msg), 0, 60)
        IO.puts("   Last Error:  #{truncated}...")
      end
    end

    IO.puts("")
  end
end
