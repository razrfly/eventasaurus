defmodule EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator do
  @moduledoc """
  Oban worker that orchestrates automated event discovery for watched cities.

  Runs on a schedule (typically daily at midnight UTC) to:
  1. Find all cities with discovery enabled
  2. Check which sources are due to run for each city
  3. Queue appropriate DiscoverySyncJob jobs for each due source
  4. Update run statistics after queueing

  ## Configuration

  The orchestrator reads configuration from the `discovery_config` JSONB field
  on each city. Each source can have:
  - `enabled`: Whether to run this source
  - `frequency_hours`: How often to run (e.g., 24 for daily)
  - `settings`: Source-specific settings (limit, radius, etc.)
  - `next_run_at`: When this source should next run

  ## Dry Run Mode

  Set `DRY_RUN=true` environment variable to log what would run without
  actually queueing jobs. Useful for testing configuration.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias EventasaurusDiscovery.Admin.{DiscoveryConfigManager, SourceOptionsBuilder}
  alias EventasaurusDiscovery.Admin.DiscoverySyncJob
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    dry_run = System.get_env("DRY_RUN") == "true"

    if dry_run do
      Logger.info("🧪 City Discovery Orchestrator: DRY RUN MODE - No jobs will be queued")
    else
      Logger.info("🌍 City Discovery Orchestrator: Starting scheduled run")
    end

    now = DateTime.utc_now()

    # Get all cities with discovery enabled
    cities = DiscoveryConfigManager.list_discovery_enabled_cities()

    Logger.info("Found #{length(cities)} cities with discovery enabled")

    # Process each city
    results =
      Enum.map(cities, fn city ->
        process_city(city, now, dry_run)
      end)

    # Summary statistics
    total_jobs = Enum.sum(Enum.map(results, fn {_, count} -> count end))

    if dry_run do
      Logger.info("🧪 DRY RUN COMPLETE: Would have queued #{total_jobs} discovery jobs")
    else
      Logger.info("✅ City Discovery Orchestrator: Queued #{total_jobs} discovery jobs")
    end

    :ok
  end

  defp process_city(city, now, dry_run) do
    Logger.info("Processing discovery for #{city.name}")

    # Get sources that are due to run
    due_sources = DiscoveryConfigManager.get_due_sources(city)

    Logger.info("  → #{length(due_sources)} sources due to run for #{city.name}")

    # Queue job for each due source
    jobs_queued =
      Enum.reduce(due_sources, 0, fn source, count ->
        case queue_discovery_job(city, source, now, dry_run) do
          {:ok, _} -> count + 1
          {:error, _} -> count
        end
      end)

    {city.id, jobs_queued}
  end

  defp queue_discovery_job(city, source, _now, dry_run) do
    # Handle both map and struct formats
    source_name = if is_map(source), do: source["name"], else: source.name

    source_settings =
      if is_map(source), do: source["settings"] || %{}, else: source.settings || %{}

    frequency_hours =
      if is_map(source), do: source["frequency_hours"] || 24, else: source.frequency_hours || 24

    limit = source_settings["limit"] || source_settings[:limit] || 100

    # Build job arguments using shared builder
    job_args =
      SourceOptionsBuilder.build_job_args(
        source_name,
        city.id,
        limit,
        source_settings
      )

    if dry_run do
      Logger.info("  🧪 [DRY RUN] Would queue #{source_name} for #{city.name}")
      Logger.debug("     Job args: #{inspect(job_args)}")
      {:ok, :dry_run}
    else
      # Queue the actual discovery sync job
      case DiscoverySyncJob.new(job_args) |> Oban.insert() do
        {:ok, job} ->
          Logger.info("  ✅ Queued #{source_name} sync for #{city.name} (job ##{job.id})")

          # Update next_run_at to prevent duplicate queueing on next orchestrator run
          next_run = DateTime.add(DateTime.utc_now(), frequency_hours * 3600, :second)

          case DiscoveryConfigManager.update_source_next_run(city.id, source_name, next_run) do
            {:ok, _} ->
              Logger.debug(
                "  📅 Updated next_run_at for #{source_name} to #{DateTime.to_iso8601(next_run)}"
              )

            {:error, reason} ->
              Logger.warning(
                "  ⚠️ Failed to update next_run_at for #{source_name}: #{inspect(reason)}"
              )
          end

          {:ok, job}

        {:error, reason} ->
          Logger.error("  ❌ Failed to queue #{source_name} for #{city.name}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
