defmodule EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJob do
  @moduledoc """
  Main orchestration job for Kupbilecik event synchronization.

  ## Discovery Strategy

  Kupbilecik uses **sitemap-based discovery**:
  1. Fetch sitemap XML files (sitemap_imprezy-{1-5}.xml)
  2. Extract event URLs from sitemaps (plain HTTP)
  3. Filter with EventFreshnessChecker (optional)
  4. Schedule EventDetailJob for each event URL
  5. EventDetailJob fetches via plain HTTP (SSR site, no JS needed)

  ## Job Flow

  ```
  SyncJob (scraper_index queue)
    ↓ Fetches sitemaps via plain HTTP
    ↓ Extracts event URLs
    ↓ Filters by freshness (optional)
    ↓ Schedules EventDetailJobs
  EventDetailJob (scraper_detail queue)
    ↓ Fetches page via plain HTTP (SSR)
    ↓ Extracts event data
    ↓ Transforms and saves to database
  ```

  ## Usage

      # Sync all events from sitemaps
      EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJob.new(%{})
      |> Oban.insert()

      # With limit (for testing)
      EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJob.new(%{"limit" => 10})
      |> Oban.insert()

      # Force mode (bypass freshness check)
      EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJob.new(%{"force" => true})
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.Kupbilecik.{Client, Config}
  alias EventasaurusDiscovery.Sources.Kupbilecik.Jobs.EventDetailJob
  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Metrics.MetricsTracker
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "kupbilecik_sync_#{Date.utc_today()}"
    limit = args["limit"]
    force = args["force"] || false
    source_id = args["source_id"] || get_source_id()

    Logger.info("""
    🗺️ Starting Kupbilecik sitemap sync
    Limit: #{limit || "unlimited"}
    Force mode: #{force}
    """)

    result =
      with {:ok, event_entries} <- Client.fetch_all_sitemap_urls(),
           {:ok, filtered_entries} <- filter_fresh_events(event_entries, source_id, limit, force),
           {:ok, scheduled_count} <- schedule_event_detail_jobs(filtered_entries) do
        Logger.info("""
        ✅ Kupbilecik sync completed
        Total URLs found: #{length(event_entries)}
        After freshness filter: #{length(filtered_entries)}
        Detail jobs scheduled: #{scheduled_count}
        """)

        {:ok,
         %{
           urls_found: length(event_entries),
           filtered_count: length(filtered_entries),
           jobs_scheduled: scheduled_count,
           force_mode: force
         }}
      end

    case result do
      {:ok, stats} ->
        MetricsTracker.record_success(job, external_id)
        {:ok, stats}

      {:error, reason} ->
        Logger.error("❌ Kupbilecik sync failed: #{inspect(reason)}")
        MetricsTracker.record_failure(job, categorize_error(reason), external_id)
        {:error, reason}
    end
  end

  # Error categorization for MetricsTracker
  # Uses 12 standard categories + 1 fallback (uncategorized_error)
  # See docs/error-handling-guide.md for category definitions
  defp categorize_error({:network_error, _}), do: :network_error
  defp categorize_error({:http_error, _}), do: :network_error
  defp categorize_error(_), do: :uncategorized_error

  # Private functions

  defp filter_fresh_events(event_entries, source_id, limit, force) do
    Logger.info("🔍 Processing #{length(event_entries)} event entries")

    # Add external_ids for freshness checking
    entries_with_ids =
      Enum.map(event_entries, fn entry ->
        Map.put(entry, :external_id, Config.generate_article_external_id(entry.event_id))
      end)

    # Filter by freshness (unless force=true)
    filtered =
      if force do
        entries_with_ids
      else
        EventFreshnessChecker.filter_events_needing_processing(entries_with_ids, source_id)
      end

    # Log efficiency metrics
    skipped = length(entries_with_ids) - length(filtered)

    Logger.info("""
    🔄 Kupbilecik Freshness Check
    Processing #{length(filtered)}/#{length(entries_with_ids)} events #{if force, do: "(Force mode)", else: "(#{skipped} fresh)"}
    """)

    # Apply limit
    limited =
      if limit do
        Enum.take(filtered, limit)
      else
        filtered
      end

    if limit && length(limited) < length(filtered) do
      Logger.info("🔢 Applying limit: #{length(limited)}/#{length(filtered)} events")
    end

    {:ok, limited}
  end

  defp schedule_event_detail_jobs(event_entries) do
    Logger.info("📅 Scheduling #{length(event_entries)} event detail jobs")

    if length(event_entries) == 0 do
      Logger.info("ℹ️ No jobs to schedule")
      {:ok, 0}
    else
      # Get source_id for child jobs
      source_id = get_source_id()

      # Schedule EventDetailJob for each event with staggered delays
      scheduled_jobs =
        event_entries
        |> Enum.with_index()
        |> Enum.map(fn {entry, idx} ->
          # Stagger jobs to respect rate limiting
          delay_seconds = idx * Config.rate_limit()

          # FLAT ARGS STRUCTURE (per Job Args Standards - Section 13)
          # - external_id at top level for easy dashboard visibility
          # - source_id instead of source slug string
          # - No nested metadata objects
          job_args = %{
            "url" => entry.url,
            "source_id" => source_id,
            "external_id" => Config.generate_article_external_id(entry.event_id),
            "event_id" => entry.event_id
          }

          EventDetailJob.new(job_args, schedule_in: delay_seconds)
          |> Oban.insert()
        end)

      # Count successful insertions
      successful_count =
        Enum.count(scheduled_jobs, fn
          {:ok, _} -> true
          _ -> false
        end)

      failed_count = length(scheduled_jobs) - successful_count

      if failed_count > 0 do
        Logger.warning("⚠️ Failed to schedule #{failed_count} detail jobs")
      end

      Logger.info(
        "✅ Successfully scheduled #{successful_count}/#{length(event_entries)} detail jobs"
      )

      {:ok, successful_count}
    end
  end

  defp get_source_id do
    case Repo.get_by(Source, slug: "kupbilecik") do
      nil ->
        Logger.warning("⚠️ Kupbilecik source not found in database")
        nil

      source ->
        source.id
    end
  end
end
