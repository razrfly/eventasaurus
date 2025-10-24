defmodule EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker do
  @moduledoc """
  Daily worker to recalculate coordinates for all discovery-enabled cities.

  Runs daily to ensure city centers stay accurate as venues are added/updated.
  Uses CityCoordinateCalculationJob's built-in 24h deduplication.

  ## Schedule

  Runs daily at 1 AM UTC via Oban cron (after midnight discovery, before 2 AM sitemap generation).

  ## Manual Triggering

  Can be manually triggered from the imports dashboard or via:

      %{} |> EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker.new() |> Oban.insert!()

  ## Design

  This worker addresses the gap where sitemap-based scrapers (like Sortiraparis) don't
  trigger coordinate updates, and ensures all active cities get daily maintenance regardless
  of scraper type.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    priority: 2

  alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
  alias EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🌍 City Coordinate Recalculation: Starting daily run")

    # Get all cities with discovery enabled
    cities = DiscoveryConfigManager.list_discovery_enabled_cities()

    Logger.info("Found #{length(cities)} active cities for coordinate recalculation")

    # Schedule coordinate calculation for each city
    results =
      Enum.map(cities, fn city ->
        case CityCoordinateCalculationJob.schedule_update(city.id) do
          {:ok, _} ->
            Logger.debug("  ✅ Scheduled coordinate update for #{city.name}")
            {:ok, city.name}

          {:error, %Ecto.Changeset{errors: [args: {"has already been scheduled", _}]}} ->
            Logger.debug("  ℹ️  Coordinate update already scheduled for #{city.name}")
            {:skipped, city.name}

          {:error, reason} ->
            Logger.warning("  ⚠️  Failed to schedule update for #{city.name}: #{inspect(reason)}")

            {:error, city.name}
        end
      end)

    scheduled_count = Enum.count(results, fn {status, _} -> status == :ok end)
    skipped_count = Enum.count(results, fn {status, _} -> status == :skipped end)
    error_count = Enum.count(results, fn {status, _} -> status == :error end)

    Logger.info("""
    ✅ City Coordinate Recalculation complete
    - Scheduled: #{scheduled_count}
    - Already scheduled: #{skipped_count}
    - Errors: #{error_count}
    - Total cities: #{length(cities)}
    """)

    {:ok,
     %{
       cities_scheduled: scheduled_count,
       cities_skipped: skipped_count,
       cities_errored: error_count,
       total_cities: length(cities)
     }}
  end
end
