defmodule EventasaurusApp.Monitoring.JobRegistry do
  @moduledoc """
  Registry of all known Oban workers and their configurations.

  This module maintains a curated list of Oban workers that should be monitored.
  For Phase 1 (MVP), this is a manual registry. Future versions could auto-discover
  workers by scanning the codebase.
  """

  alias EventasaurusDiscovery.Sources.Source

  @doc """
  Returns a list of all registered job configurations.

  Each configuration includes:
  - worker: Full module name as string (e.g., "Eventasaurus.Workers.SitemapWorker")
  - display_name: Human-readable name
  - category: :discovery | :scheduled | :maintenance | :background
  - queue: Queue name
  - schedule: Cron expression (for scheduled jobs) or nil
  - description: What this job does

  Includes regularly scheduled automated jobs (discovery, scheduled cron, maintenance).
  Excludes on-demand background jobs triggered by user actions.
  """
  def list_all_jobs do
    scheduled_jobs() ++ discovery_jobs() ++ maintenance_jobs()
  end

  @doc """
  Get configuration for a specific worker by name.
  """
  def get_job_config(worker_name) when is_binary(worker_name) do
    list_all_jobs()
    |> Enum.find(&(&1.worker == worker_name))
  end

  # Scheduled Cron Jobs (auto-discovered from config/config.exs Oban.Plugins.Cron)
  defp scheduled_jobs do
    # Parse Oban cron configuration at runtime
    cron_jobs = get_cron_jobs_from_config()

    # Map each cron job to our job structure with metadata overrides
    Enum.map(cron_jobs, fn {schedule, worker} ->
      worker_name = module_to_string(worker)

      %{
        worker: worker_name,
        display_name: get_display_name(worker_name),
        category: :scheduled,
        queue: extract_queue_from_worker(worker_name),
        schedule: schedule,
        description: get_description(worker_name, schedule)
      }
    end) ++ manual_scheduled_jobs()
  end

  # Extract cron jobs from Oban configuration
  defp get_cron_jobs_from_config do
    oban_config = Application.get_env(:eventasaurus, Oban, [])

    oban_config[:plugins]
    |> Enum.find_value(fn
      {Oban.Plugins.Cron, opts} -> opts[:crontab] || []
      _ -> nil
    end) || []
  end

  # Manual scheduled jobs that aren't in cron config
  defp manual_scheduled_jobs do
    worker_name = "EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob"

    [
      %{
        worker: worker_name,
        display_name: "Now Playing Movies Sync",
        category: :scheduled,
        queue: extract_queue_from_worker(worker_name),
        schedule: nil,
        description: "Syncs now playing movies from TMDB"
      }
    ]
  end

  # Display name overrides for scheduled jobs
  defp get_display_name("Eventasaurus.Workers.SitemapWorker"), do: "Sitemap Generator"

  defp get_display_name("EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator"),
    do: "City Discovery Orchestrator"

  defp get_display_name("EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker"),
    do: "City Coordinate Recalculation"

  defp get_display_name("EventasaurusApp.Workers.UnsplashRefreshWorker"),
    do: "Unsplash Images Refresh"

  defp get_display_name(worker_name) do
    # Fallback: humanize the module name
    worker_name
    |> String.split(".")
    |> List.last()
    |> String.replace("Worker", "")
    |> humanize_string()
  end

  # Extract queue from worker module configuration
  defp extract_queue_from_worker(worker_name) when is_binary(worker_name) do
    try do
      # Convert string to module atom, handling existing Elixir prefix
      module_name =
        if String.starts_with?(worker_name, "Elixir."),
          do: worker_name,
          else: "Elixir.#{worker_name}"

      module = String.to_existing_atom(module_name)

      # Ensure module is loaded
      Code.ensure_loaded(module)

      # Get Oban worker configuration
      # Oban workers store their config in __opts__/0 function
      if function_exported?(module, :__opts__, 0) do
        opts = apply(module, :__opts__, [])
        queue = Keyword.get(opts, :queue, :default)
        to_string(queue)
      else
        "default"
      end
    rescue
      # Module doesn't exist
      ArgumentError -> "default"
      # Any other error
      _ -> "default"
    end
  end

  # Description generation based on schedule
  defp get_description("Eventasaurus.Workers.SitemapWorker", _schedule),
    do: "Generates XML sitemaps daily at 2 AM UTC"

  defp get_description("EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator", _schedule),
    do: "Orchestrates city-wide event discovery at midnight UTC"

  defp get_description(
         "EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker",
         _schedule
       ),
       do: "Recalculates city coordinates daily at 1 AM UTC"

  defp get_description("EventasaurusApp.Workers.UnsplashRefreshWorker", _schedule),
    do: "Refreshes Unsplash city images daily at 3 AM UTC"

  defp get_description(_worker, schedule) do
    # Fallback: generate description from cron schedule
    "Runs #{humanize_cron_schedule(schedule)}"
  end

  # Convert module atom to string
  defp module_to_string(module) when is_atom(module) do
    module |> Module.split() |> Enum.join(".")
  end

  # Humanize string (CamelCase to Title Case)
  defp humanize_string(str) do
    str
    |> String.replace(~r/([A-Z])/, " \\1")
    |> String.trim()
  end

  # Convert cron schedule to human-readable format
  defp humanize_cron_schedule("0 0 * * *"), do: "daily at midnight UTC"
  defp humanize_cron_schedule("0 1 * * *"), do: "daily at 1 AM UTC"
  defp humanize_cron_schedule("0 2 * * *"), do: "daily at 2 AM UTC"
  defp humanize_cron_schedule("0 3 * * *"), do: "daily at 3 AM UTC"
  defp humanize_cron_schedule("0 4 * * *"), do: "daily at 4 AM UTC"
  defp humanize_cron_schedule(schedule), do: "on schedule: #{schedule}"

  # Discovery Jobs (auto-discovered from SourceRegistry)
  defp discovery_jobs do
    # Get parent jobs from SourceRegistry
    parent_jobs =
      EventasaurusDiscovery.Sources.SourceRegistry.sources_map()
      |> Enum.map(fn {source_slug, _job_module} ->
        worker = get_parent_worker_for_source(source_slug)

        %{
          worker: worker,
          display_name: humanize_source_name(source_slug),
          category: :discovery,
          queue: extract_queue_from_worker(worker),
          schedule: nil,
          description: "Syncs events from #{humanize_source_name(source_slug)}"
        }
      end)

    # Append manually defined child jobs (spawned by parent jobs)
    parent_jobs ++ child_discovery_jobs()
  end

  # Override mapping for sources that don't use standard SyncJob pattern
  defp get_parent_worker_for_source("bandsintown"),
    do: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.IndexPageJob"

  defp get_parent_worker_for_source("ticketmaster"),
    do: "EventasaurusDiscovery.Apis.Ticketmaster.Jobs.CitySyncJob"

  defp get_parent_worker_for_source("cinema-city"),
    do: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob"

  defp get_parent_worker_for_source("repertuary"),
    do: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob"

  defp get_parent_worker_for_source("karnet"),
    do: "EventasaurusDiscovery.Sources.Karnet.Jobs.IndexPageJob"

  # Default: use SourceRegistry mapping (converts module to string)
  defp get_parent_worker_for_source(source_slug) do
    case EventasaurusDiscovery.Sources.SourceRegistry.get_sync_job(source_slug) do
      {:ok, module} -> module |> Module.split() |> Enum.join(".")
      # Fallback for unknown sources
      {:error, _} -> "Unknown.Worker"
    end
  end

  # Convert source slug to display name
  # Uses Source.get_display_name/1 as single source of truth
  defp humanize_source_name(slug) do
    Source.get_display_name(slug) <> " Sync"
  end

  # No longer needed - queues extracted from worker modules via extract_queue_from_worker/1

  # Child jobs auto-detected by convention (spawned by parent jobs, hidden from dashboard)
  defp child_discovery_jobs do
    # Get all parent job worker names for comparison
    parent_workers =
      EventasaurusDiscovery.Sources.SourceRegistry.sources_map()
      |> Enum.map(fn {source_slug, _} -> get_parent_worker_for_source(source_slug) end)
      |> MapSet.new()

    # Query Oban for all discovery-related workers that have been executed
    discovery_workers = get_all_discovery_workers()

    # Filter out parent jobs to identify child jobs
    discovery_workers
    |> Enum.reject(&MapSet.member?(parent_workers, &1))
    |> Enum.map(&build_child_job_metadata/1)
  end

  # Query Oban jobs table for all distinct discovery worker modules
  # NOTE: This query runs on every dashboard load. Performance optimizations:
  # 1. Add database index on oban_jobs.worker column (recommended)
  # 2. Cache results with 5-minute TTL if this becomes a bottleneck
  # Current approach maintains true auto-discovery - new child jobs appear immediately
  # Uses read replica to reduce load on primary database
  defp get_all_discovery_workers do
    import Ecto.Query

    EventasaurusApp.Repo.replica().all(
      from(j in Oban.Job,
        where:
          fragment(
            "? LIKE 'EventasaurusDiscovery.Sources.%' OR ? LIKE 'EventasaurusDiscovery.Apis.%'",
            j.worker,
            j.worker
          ),
        distinct: true,
        select: j.worker
      )
    )
  end

  # Build metadata for a child job based on naming conventions
  defp build_child_job_metadata(worker) do
    # Extract source name and job type from worker module
    # E.g., "EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob"
    parts = String.split(worker, ".")
    source_name = Enum.at(parts, 3) || "Unknown"
    job_type = List.last(parts) || "Unknown"

    %{
      worker: worker,
      display_name: humanize_child_job_name(source_name, job_type),
      category: :discovery,
      queue: extract_queue_from_worker(worker),
      schedule: nil,
      description: generate_child_job_description(source_name, job_type),
      show_in_dashboard: false
    }
  end

  # Humanize child job display name
  defp humanize_child_job_name(source_name, job_type) do
    source_display = source_name |> humanize_string()
    job_display = job_type |> String.replace("Job", "") |> humanize_string()
    "#{source_display} #{job_display}"
  end

  # No longer needed - queues extracted from worker modules via extract_queue_from_worker/1

  # Generate description based on job type
  defp generate_child_job_description(source_name, job_type) do
    source_display = source_name |> humanize_string()

    cond do
      String.ends_with?(job_type, "DetailJob") ->
        "Fetches detailed event information from #{source_display}"

      String.ends_with?(job_type, "EnrichmentJob") ->
        "Enriches events with additional information from #{source_display}"

      String.ends_with?(job_type, "ProcessorJob") ->
        "Processes events from #{source_display}"

      true ->
        "Background processing for #{source_display}"
    end
  end

  # Maintenance and Background Jobs
  defp maintenance_jobs do
    [
      "EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob",
      "EventasaurusDiscovery.Geocoding.ProviderIdBackfillJob"
      # VenueImages.BackfillOrchestratorJob removed - migrated to R2/cached_images (Issue #2977)
    ]
    |> Enum.map(fn worker_name ->
      %{
        worker: worker_name,
        display_name: humanize_maintenance_job_name(worker_name),
        category: :maintenance,
        queue: extract_queue_from_worker(worker_name),
        schedule: nil,
        description: generate_maintenance_job_description(worker_name)
      }
    end)
  end

  # Humanize maintenance job names
  defp humanize_maintenance_job_name("EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob"),
    do: "City Coordinate Calculation"

  defp humanize_maintenance_job_name("EventasaurusDiscovery.Geocoding.ProviderIdBackfillJob"),
    do: "Geocoding Provider ID Backfill"

  # VenueImages.BackfillOrchestratorJob removed - migrated to R2/cached_images (Issue #2977)

  defp humanize_maintenance_job_name(worker_name) do
    worker_name
    |> String.split(".")
    |> List.last()
    |> String.replace("Job", "")
    |> humanize_string()
  end

  # Generate maintenance job descriptions
  defp generate_maintenance_job_description(
         "EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob"
       ),
       do: "Calculates coordinates for cities"

  defp generate_maintenance_job_description(
         "EventasaurusDiscovery.Geocoding.ProviderIdBackfillJob"
       ),
       do: "Backfills provider IDs for existing geocoded venues"

  # VenueImages.BackfillOrchestratorJob removed - migrated to R2/cached_images (Issue #2977)

  defp generate_maintenance_job_description(_worker_name),
    do: "Maintenance background job"
end
