defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.IndexPageJob do
  @moduledoc """
  Processes events from Speed Quizzing index page and enqueues detail jobs.

  ## Workflow
  1. Receive events array from SyncJob
  2. Filter using EventFreshnessChecker (skip fresh events within 7 days)
  3. Apply limit if provided (for testing)
  4. Enqueue EventDetailJob for each event
  5. EventDetailJob will fetch detail page and process venue/event data

  ## Two-Stage Architecture
  Unlike Inquizition, Speed Quizzing requires detail page scraping:
  - Index provides basic event list (id, name, date, time)
  - Detail pages provide venue, performer, and full event data
  - EventDetailJob handles venue processing and event transformation
  - EventFreshnessChecker provides 80-90% API call reduction
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 1

  require Logger

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Sources.SpeedQuizzing
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "speed_quizzing_index_#{Date.utc_today()}"
    source_id = args["source_id"]
    events = args["events"] || []
    limit = args["limit"]
    force = args["force"] || false

    Logger.info("🔄 Processing #{length(events)} Speed Quizzing events")

    # Filter events using freshness checker (unless force=true)
    events_to_process = filter_fresh_events(events, source_id, limit, force)

    skipped_count = length(events) - length(events_to_process)

    Logger.info("""
    📋 Enqueueing #{length(events_to_process)} detail jobs
    #{if force, do: "(Force mode - freshness check bypassed)", else: "(#{skipped_count} events skipped - recently updated)"}
    """)

    # Enqueue detail jobs for each event
    result = enqueue_detail_jobs(events_to_process, source_id)
    MetricsTracker.record_success(job, external_id)
    result
  end

  # Filter out events that were recently updated (default: 7 days)
  # In force mode, skip filtering to process all events
  defp filter_fresh_events(events, source_id, limit, force) do
    # Generate external_ids for each event (prefer event_id, fallback to id)
    events_with_external_ids =
      Enum.map(events, fn event ->
        id = event["event_id"] || event["id"]
        Map.put(event, "external_id", "speed-quizzing-#{id}")
      end)

    # Filter out events that were recently updated (unless force=true)
    events_to_process =
      if force do
        events_with_external_ids
      else
        EventFreshnessChecker.filter_events_needing_processing(
          events_with_external_ids,
          source_id
        )
      end

    # Apply limit if provided (for testing)
    if limit do
      Enum.take(events_to_process, limit)
    else
      events_to_process
    end
  end

  # Enqueue an EventDetailJob for each event
  defp enqueue_detail_jobs(events, source_id) do
    jobs =
      Enum.map(events, fn event ->
        # Index JSON uses "event_id" not "id"
        event_id = event["event_id"] || event["id"]

        %{
          "source_id" => source_id,
          "event_id" => event_id,
          "event_data" => event
        }
        |> SpeedQuizzing.Jobs.EventDetailJob.new()
      end)

    # Insert all jobs
    inserted_jobs = Oban.insert_all(jobs)
    count = length(inserted_jobs)
    Logger.info("✅ Enqueued #{count} detail jobs for Speed Quizzing")
    {:ok, %{detail_jobs_enqueued: count}}
  end
end
