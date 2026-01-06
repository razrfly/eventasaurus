defmodule EventasaurusApp.Workers.ObanJobSanitizerWorker do
  @moduledoc """
  Worker to detect and fix corrupted Oban jobs every 30 minutes.

  ## Background (Issue #3172)

  Oban jobs can get into corrupted states due to:
  - Deploys during job execution (shutdown race conditions)
  - Connection pool exhaustion causing timeout errors
  - Priority 0 + exhausted attempts blocking queues

  ## Detection Patterns

  1. **Zombie Available Jobs**: Jobs in 'available' state with:
     - `attempt >= max_attempts` (should be discarded but aren't)
     - `scheduled_at` in the past but never picked up

  2. **Stuck Executing Jobs**: Jobs in 'executing' state with:
     - `attempted_at` older than Lifeline's `rescue_after` (5 minutes)
     - These should have been rescued by Lifeline but weren't

  3. **Priority 0 Blockers**: Jobs with priority 0 that are blocking queues
     - Priority 0 means "pick me first" but if stuck, blocks everything

  ## Fix Strategy

  For each corrupted job:
  1. If `attempt >= max_attempts`: Discard the job
  2. If stuck executing: Let Lifeline handle it (just log for visibility)
  3. If priority 0 blocker: Bump priority to 3 (normal) so queue unblocks

  ## Metrics

  Logs counts of detected and fixed jobs for monitoring.
  Can be correlated with Oban health dashboards.

  ## Configuration

  Add to crontab in `config/runtime.exs`:

      {"*/30 * * * *", EventasaurusApp.Workers.ObanJobSanitizerWorker}

  ## Manual Trigger

      EventasaurusApp.Workers.ObanJobSanitizerWorker.new(%{})
      |> Oban.insert()

  Or check health without fixing:

      mix audit.oban_health
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  import Ecto.Query, warn: false
  require Logger

  @doc """
  Performs the sanitization check and fixes corrupted jobs.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    Logger.info("[ObanJobSanitizerWorker] Starting sanitization check [job #{job_id}]")
    start_time = System.monotonic_time(:millisecond)

    # Use ObanRepo for Oban operations
    repo = EventasaurusApp.ObanRepo

    # Detect and fix each corruption pattern
    zombie_stats = fix_zombie_available_jobs(repo)
    priority_stats = fix_priority_zero_blockers(repo)
    stuck_stats = detect_stuck_executing_jobs(repo)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    total_detected = zombie_stats.detected + priority_stats.detected + stuck_stats.detected
    total_fixed = zombie_stats.fixed + priority_stats.fixed

    Logger.info("""
    [ObanJobSanitizerWorker] Sanitization complete in #{duration_ms}ms
      Zombie available: #{zombie_stats.detected} detected, #{zombie_stats.fixed} discarded
      Priority 0 blockers: #{priority_stats.detected} detected, #{priority_stats.fixed} bumped
      Stuck executing: #{stuck_stats.detected} detected (Lifeline will handle)
      Total: #{total_detected} detected, #{total_fixed} fixed
    """)

    {:ok,
     %{
       duration_ms: duration_ms,
       zombie_jobs: zombie_stats,
       priority_blockers: priority_stats,
       stuck_jobs: stuck_stats,
       total_detected: total_detected,
       total_fixed: total_fixed
     }}
  end

  @doc """
  Detects corrupted jobs without fixing them (for CLI audit).

  Returns a map with detection results for each pattern.
  """
  def detect_all do
    repo = EventasaurusApp.ObanRepo

    %{
      zombie_available: detect_zombie_available_jobs(repo),
      priority_zero_blockers: detect_priority_zero_blockers(repo),
      stuck_executing: detect_stuck_executing_jobs_list(repo)
    }
  end

  # ===========================================================================
  # Zombie Available Jobs
  # ===========================================================================
  # Jobs in 'available' state with exhausted attempts that should be discarded

  defp fix_zombie_available_jobs(repo) do
    zombies = detect_zombie_available_jobs(repo)

    fixed_count =
      if length(zombies) > 0 do
        now = DateTime.utc_now()
        ids = Enum.map(zombies, & &1.id)

        # Use raw SQL to append to the errors array (fragment doesn't work in update_all set)
        error_msg = "Discarded by ObanJobSanitizerWorker: zombie job with exhausted attempts"

        case repo.query(
               """
               UPDATE oban_jobs
               SET state = 'discarded',
                   discarded_at = $1,
                   errors = array_append(errors, $2::jsonb)
               WHERE id = ANY($3)
               """,
               [now, Jason.encode!(%{at: now, error: error_msg}), ids]
             ) do
          {:ok, result} ->
            Logger.warning(
              "[ObanJobSanitizerWorker] Discarded #{result.num_rows} zombie available jobs: #{inspect(ids)}"
            )

            result.num_rows

          {:error, reason} ->
            Logger.error(
              "[ObanJobSanitizerWorker] Failed to discard zombie jobs: #{inspect(reason)}"
            )

            0
        end
      else
        0
      end

    %{detected: length(zombies), fixed: fixed_count}
  end

  defp detect_zombie_available_jobs(repo) do
    # Jobs that are available but have exhausted their attempts
    # These should never happen - they should transition to discarded
    query =
      from(j in "oban_jobs",
        where: j.state == "available",
        where: j.attempt >= j.max_attempts,
        where: j.max_attempts > 0,
        select: %{id: j.id, queue: j.queue, worker: j.worker, attempt: j.attempt}
      )

    repo.all(query)
  end

  # ===========================================================================
  # Priority Zero Blockers
  # ===========================================================================
  # Priority 0 jobs that are stuck can block entire queues

  defp fix_priority_zero_blockers(repo) do
    blockers = detect_priority_zero_blockers(repo)

    fixed_count =
      if length(blockers) > 0 do
        ids = Enum.map(blockers, & &1.id)

        # Bump priority to 3 (normal) so they don't block the queue
        {count, _} =
          repo.update_all(
            from(j in "oban_jobs", where: j.id in ^ids),
            set: [priority: 3]
          )

        Logger.warning(
          "[ObanJobSanitizerWorker] Bumped priority on #{count} blocking jobs: #{inspect(ids)}"
        )

        count
      else
        0
      end

    %{detected: length(blockers), fixed: fixed_count}
  end

  defp detect_priority_zero_blockers(repo) do
    # Priority 0 jobs that have been available for > 5 minutes
    # and have failed at least once - they're blocking the queue
    five_minutes_ago = DateTime.add(DateTime.utc_now(), -300, :second)

    query =
      from(j in "oban_jobs",
        where: j.state == "available",
        where: j.priority == 0,
        where: j.attempt > 0,
        where: j.scheduled_at < ^five_minutes_ago,
        select: %{id: j.id, queue: j.queue, worker: j.worker, attempt: j.attempt}
      )

    repo.all(query)
  end

  # ===========================================================================
  # Stuck Executing Jobs
  # ===========================================================================
  # Jobs stuck in executing state longer than Lifeline's rescue_after

  defp detect_stuck_executing_jobs(repo) do
    stuck = detect_stuck_executing_jobs_list(repo)

    # We don't fix these - Lifeline should handle them
    # But we log for visibility since Lifeline might not be working
    if length(stuck) > 0 do
      Logger.warning(
        "[ObanJobSanitizerWorker] Found #{length(stuck)} stuck executing jobs (Lifeline should rescue): #{inspect(Enum.map(stuck, & &1.id))}"
      )
    end

    %{detected: length(stuck), fixed: 0}
  end

  defp detect_stuck_executing_jobs_list(repo) do
    # Lifeline rescue_after is 300 seconds - check for jobs older than that
    # Add a buffer of 60 seconds (so 6 minutes total)
    six_minutes_ago = DateTime.add(DateTime.utc_now(), -360, :second)

    query =
      from(j in "oban_jobs",
        where: j.state == "executing",
        where: j.attempted_at < ^six_minutes_ago,
        select: %{
          id: j.id,
          queue: j.queue,
          worker: j.worker,
          attempted_at: j.attempted_at
        }
      )

    repo.all(query)
  end
end
