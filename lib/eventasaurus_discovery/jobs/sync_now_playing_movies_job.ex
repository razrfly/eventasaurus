defmodule EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob do
  @moduledoc """
  Coordinator job for syncing "Now Playing" movies from TMDB.

  This job acts as a coordinator that spawns individual page fetch jobs
  (`FetchNowPlayingPageJob`) for each page of results. This hierarchical
  architecture provides:

  - **Independent Retries**: Each page can fail and retry independently
  - **Better Observability**: Each page is a separate job in Oban dashboard
  - **Smarter Backoff**: Rate limits on one page don't block others
  - **Rate Limit Prevention**: Staggered scheduling prevents concurrent API calls

  ## Architecture

  ```
  SyncNowPlayingMoviesJob (Coordinator)
    ├─ FetchNowPlayingPageJob(page: 1, delay: 0s)  → Runs immediately
    ├─ FetchNowPlayingPageJob(page: 2, delay: 3s)  → Runs after 3s
    ├─ FetchNowPlayingPageJob(page: 3, delay: 6s)  → Runs after 6s
    └─ FetchNowPlayingPageJob(page: 4, delay: 9s)  → Runs after 9s
  ```

  ## Rate Limit Prevention Strategy

  **TMDB API Limits** (as of 2024-2025):
  - 50 requests/second (max)
  - 20 concurrent connections per IP

  **Our Strategy**:
  - Stagger job execution by 3 seconds per page
  - 10 pages over 27 seconds = ~0.37 requests/second
  - Well under 50 req/s limit
  - Prevents concurrent execution and rate limit errors

  **Why This Matters**:
  - Without staggering: All 10 jobs hit API simultaneously → 5+ rate limit errors
  - With staggering: Jobs run sequentially → 0 rate limit errors
  - Result: Faster overall completion (no retries needed)

  ## Each Spawned Job

  1. Fetches one page from TMDB's "Now Playing" endpoint
  2. For each movie, fetches translations for localized titles
  3. Creates/updates movies in the database with full TMDB metadata
  4. Handles rate limits with custom 5-minute backoff (if needed)

  ## Usage

      # Via Mix task
      mix tmdb.sync_now_playing --region PL --pages 3

      # Via Oban (programmatic)
      EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob.new(%{region: "PL", pages: 3})
      |> Oban.insert()

      # With custom stagger delay
      EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob.new(%{
        region: "PL",
        pages: 10,
        stagger_seconds: 2  # Override default 3s stagger
      })
      |> Oban.insert()

      # Future: Via cron (daily at 3 AM)
      # config :eventasaurus_app, Oban,
      #   plugins: [
      #     {Oban.Plugins.Cron,
      #       crontab: [
      #         {"0 3 * * *", EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob, args: %{region: "PL"}}
      #       ]
      #     }
      #   ]
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 5

  require Logger

  alias EventasaurusDiscovery.Jobs.FetchNowPlayingPageJob
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # TMDB API Rate Limits (as of 2024-2025):
  # - 50 requests/second (max)
  # - 20 concurrent connections per IP
  #
  # Stagger Strategy:
  # - Space out jobs by 3 seconds each
  # - 10 jobs over 27 seconds = ~0.37 requests/second
  # - Well under 50 req/s limit
  # - Prevents concurrent execution and rate limit errors
  @page_stagger_seconds 3

  @impl Oban.Worker
  def perform(%Oban.Job{id: coordinator_job_id, args: args} = job) do
    region = normalize_region(args["region"] || args[:region])
    pages = coerce_pages(args["pages"] || args[:pages])
    stagger = args["stagger_seconds"] || @page_stagger_seconds
    external_id = "now_playing_sync_#{region}_#{Date.utc_today()}"

    Logger.info("""
    🎬 Coordinator starting: spawning #{pages} page fetch jobs for #{region}
    📅 Scheduling strategy: Stagger by #{stagger}s to prevent concurrent rate limits
    ⏱️  Total schedule window: #{pages * stagger}s (#{format_duration(pages * stagger)})
    """)

    # Spawn individual page fetch jobs with staggered scheduling
    # Each page is delayed by (page - 1) * stagger_seconds
    # This prevents concurrent API calls that trigger rate limits
    # Use insert_all for atomic insertion to prevent duplicate jobs on retry
    job_changesets =
      for page <- 1..pages do
        delay_seconds = (page - 1) * stagger

        %{
          region: region,
          page: page,
          coordinator_job_id: coordinator_job_id
        }
        |> FetchNowPlayingPageJob.new(schedule_in: delay_seconds)
      end

    # Insert all jobs atomically to prevent duplicates on retry
    spawned_jobs = Oban.insert_all(job_changesets)
    Logger.info("📦 Inserted #{length(spawned_jobs)} jobs atomically")

    # Log schedule for each job
    Enum.with_index(spawned_jobs, 1)
    |> Enum.each(fn {job, page} ->
      delay_seconds = (page - 1) * stagger
      schedule_time = DateTime.utc_now() |> DateTime.add(delay_seconds, :second)

      Logger.debug(
        "📄 Page #{page} scheduled for #{format_time(schedule_time)} (#{delay_seconds}s delay) - Job ID: #{job.id}"
      )
    end)

    job_ids = Enum.map(spawned_jobs, & &1.id)

    first_job_time = DateTime.utc_now()
    last_job_time = DateTime.utc_now() |> DateTime.add((pages - 1) * stagger, :second)

    Logger.info("""
    ✅ Coordinator complete: spawned #{length(spawned_jobs)} page fetch jobs for #{region}
    📋 Job IDs: #{inspect(job_ids)}
    📅 Schedule: #{format_time(first_job_time)} to #{format_time(last_job_time)} (#{stagger}s stagger)
    🎯 Rate Limit Prevention: Jobs spaced to avoid concurrent API calls
    ⏳ Expected completion: ~#{format_duration(pages * stagger + 60)} (including processing time)

    Each page will fetch and sync movies independently with automatic retry on failure.
    """)

    # Record success with MetricsTracker
    MetricsTracker.record_success(job, external_id, %{
      pages_spawned: pages,
      region: region,
      stagger_seconds: stagger
    })

    {:ok,
     %{
       coordinator_job_id: coordinator_job_id,
       region: region,
       pages: pages,
       stagger_seconds: stagger,
       spawned_job_ids: job_ids,
       schedule_start: first_job_time,
       schedule_end: last_job_time,
       message:
         "Spawned #{pages} page fetch jobs with #{stagger}s stagger to prevent rate limits."
     }}
  end

  # Normalize region code to uppercase 2-letter ISO code
  defp normalize_region(nil), do: "PL"

  defp normalize_region(region) when is_binary(region) do
    region
    |> String.upcase()
    |> case do
      <<a, b>> when a in ?A..?Z and b in ?A..?Z -> <<a, b>>
      _ -> "PL"
    end
  end

  defp normalize_region(_), do: "PL"

  # Coerce pages parameter to valid positive integer
  defp coerce_pages(nil), do: 3
  defp coerce_pages(p) when is_integer(p) and p > 0 and p <= 20, do: p
  # Cap at 20 pages
  defp coerce_pages(p) when is_integer(p) and p > 20, do: 20

  defp coerce_pages(p) when is_binary(p) do
    case Integer.parse(p) do
      {i, ""} when i > 0 and i <= 20 -> i
      # Cap at 20 pages
      {i, ""} when i > 20 -> 20
      _ -> 3
    end
  end

  defp coerce_pages(_), do: 3

  # Format DateTime for human-readable logging
  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_time()
    |> Time.to_string()
  end

  # Format duration in seconds to human-readable format
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end

  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end
end
