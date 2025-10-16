defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.IndexJob do
  @moduledoc """
  Processes events from Speed Quizzing index page and enqueues detail jobs.

  ## Workflow
  1. Receive events array from SyncJob
  2. Filter using EventFreshnessChecker (skip fresh events within 7 days)
  3. Apply limit if provided (for testing)
  4. Enqueue DetailJob for each event
  5. DetailJob will fetch detail page and process venue/event data

  ## Two-Stage Architecture
  Unlike Inquizition, Speed Quizzing requires detail page scraping:
  - Index provides basic event list (id, name, date, time)
  - Detail pages provide venue, performer, and full event data
  - DetailJob handles venue processing and event transformation
  - EventFreshnessChecker provides 80-90% API call reduction
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 1

  require Logger

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Sources.SpeedQuizzing

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source_id = args["source_id"]
    events = args["events"]
    limit = args["limit"]

    Logger.info("🔄 Processing #{length(events)} Speed Quizzing events")

    # Filter events using freshness checker
    events_to_process = filter_fresh_events(events, source_id, limit)

    Logger.info("""
    📋 Enqueueing #{length(events_to_process)} detail jobs
    (#{length(events) - length(events_to_process)} events skipped - recently updated)
    """)

    # Enqueue detail jobs for each event
    enqueue_detail_jobs(events_to_process, source_id)
  end

  # Filter out events that were recently updated (default: 7 days)
  defp filter_fresh_events(events, source_id, limit) do
    # Generate external_ids for each event
    events_with_external_ids = Enum.map(events, fn event ->
      Map.put(event, "external_id", "speed-quizzing-#{event["id"]}")
    end)

    # Filter out events that were recently updated
    events_to_process = EventFreshnessChecker.filter_events_needing_processing(
      events_with_external_ids,
      source_id
    )

    # Apply limit if provided (for testing)
    if limit do
      Enum.take(events_to_process, limit)
    else
      events_to_process
    end
  end

  # Enqueue a DetailJob for each event
  defp enqueue_detail_jobs(events, source_id) do
    jobs = Enum.map(events, fn event ->
      # Index JSON uses "event_id" not "id"
      event_id = event["event_id"] || event["id"]

      %{
        "source_id" => source_id,
        "event_id" => event_id,
        "event_data" => event
      }
      |> SpeedQuizzing.Jobs.DetailJob.new()
    end)

    # Insert all jobs
    {count, _} = Oban.insert_all(jobs)
    Logger.info("✅ Enqueued #{count} detail jobs for Speed Quizzing")
    {:ok, %{detail_jobs_enqueued: count}}
  end
end
