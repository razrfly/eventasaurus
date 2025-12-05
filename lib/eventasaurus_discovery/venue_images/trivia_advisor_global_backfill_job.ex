defmodule EventasaurusDiscovery.VenueImages.TriviaAdvisorGlobalBackfillJob do
  @moduledoc """
  Global orchestrator for migrating ALL venue images from Trivia Advisor database.

  This job coordinates the migration across all cities by spawning individual
  TriviaAdvisorBackfillJob workers for each city that has venues with coordinates.

  ## Architecture

  ```
  TriviaAdvisorGlobalBackfillJob (global orchestrator)
    └─ For each city with venues:
        └─ Spawns TriviaAdvisorBackfillJob (city orchestrator)
            └─ Spawns TriviaAdvisorImageUploadJob for each matched venue
  ```

  ## Usage

      # Start global migration (all cities, unlimited venues per city)
      TriviaAdvisorGlobalBackfillJob.enqueue()

      # Dry run to preview what would happen
      TriviaAdvisorGlobalBackfillJob.enqueue(dry_run: true)

      # Force re-process venues that already have images
      TriviaAdvisorGlobalBackfillJob.enqueue(force: true)

  ## Job Arguments

  - `:dry_run` - Optional. Preview changes without spawning city jobs (default: false)
  - `:force` - Optional. Force re-process venues with existing images (default: false)

  ## Failure Handling

  Each city is processed independently. If one city fails:
  - Other cities continue processing
  - Failed city is recorded in metadata
  - Job still completes successfully (partial success)

  ## Job Metadata

      %{
        "status" => "completed",
        "total_cities" => 23,
        "cities_processed" => 23,
        "cities_failed" => 0,
        "jobs_spawned" => 23,
        "spawned_job_ids" => [101, 102, ...],
        "city_results" => [
          %{"city_id" => 1, "city_name" => "Warsaw", "job_id" => 101, "status" => "spawned"},
          ...
        ],
        "failed_cities" => [],
        "processed_at" => "2024-01-01T00:00:00Z"
      }
  """

  use Oban.Worker,
    queue: :venue_backfill,
    max_attempts: 1,
    priority: 1

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob
  import Ecto.Query

  @doc """
  Enqueues a global Trivia Advisor migration job.

  ## Options

  - `:dry_run` - Preview changes without spawning city jobs (default: false)
  - `:force` - Force re-process venues with existing images (default: false)

  ## Examples

      # Start full migration
      TriviaAdvisorGlobalBackfillJob.enqueue()

      # Dry run first
      TriviaAdvisorGlobalBackfillJob.enqueue(dry_run: true)

  """
  @spec enqueue(keyword()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(args \\ []) when is_list(args) do
    args_map =
      args
      |> Enum.into(%{})
      |> convert_keys_to_strings()

    args_map
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    dry_run = Map.get(args, "dry_run", false)
    force = Map.get(args, "force", false)

    Logger.info("""
    🌍 Starting GLOBAL Trivia Advisor image migration:
       - Dry Run: #{dry_run}
       - Force: #{force}
    """)

    # Validate Trivia Advisor database connection first
    ta_db_url = System.get_env("TRIVIA_ADVISOR_DATABASE_URL")

    unless ta_db_url do
      error_msg = "TRIVIA_ADVISOR_DATABASE_URL not set in environment"
      Logger.error("❌ #{error_msg}")

      store_failure_meta(job, %{
        status: "failed",
        error: error_msg
      })

      {:error, error_msg}
    else
      # Get all cities with venues that have coordinates
      cities = get_cities_with_venue_coordinates()

      Logger.info("📍 Found #{length(cities)} cities with venue coordinates")

      if dry_run do
        # Dry run - just report what would happen
        results = preview_migration(cities)
        store_success_meta(job, results, dry_run)

        Logger.info("""
        ✅ [DRY RUN] Global migration preview completed:
           - Total cities: #{results.total_cities}
           - Would spawn: #{results.total_cities} city-level jobs
        """)

        :ok
      else
        # Execute migration - spawn city jobs
        results = execute_migration(cities, force)
        store_success_meta(job, results, dry_run)

        Logger.info("""
        ✅ Global migration orchestrator completed:
           - Cities processed: #{results.cities_processed}/#{results.total_cities}
           - Jobs spawned: #{results.jobs_spawned}
           - Failed cities: #{results.cities_failed}
        """)

        :ok
      end
    end
  end

  # Private Functions

  defp get_cities_with_venue_coordinates do
    # Get all cities that have at least one venue with coordinates
    Repo.all(
      from(c in City,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.city_id == c.id,
        where: not is_nil(v.latitude) and not is_nil(v.longitude),
        group_by: c.id,
        select: %{
          id: c.id,
          name: c.name,
          venue_count: count(v.id)
        },
        order_by: [desc: count(v.id)]
      )
    )
  end

  defp preview_migration(cities) do
    city_results =
      Enum.map(cities, fn city ->
        %{
          "city_id" => city.id,
          "city_name" => city.name,
          "venue_count" => city.venue_count,
          "status" => "would_spawn"
        }
      end)

    %{
      total_cities: length(cities),
      cities_processed: length(cities),
      cities_failed: 0,
      jobs_spawned: length(cities),
      spawned_job_ids: [],
      city_results: city_results,
      failed_cities: []
    }
  end

  defp execute_migration(cities, force) do
    # Spawn a TriviaAdvisorBackfillJob for each city with unlimited processing
    results =
      Enum.map(cities, fn city ->
        spawn_city_job(city, force)
      end)

    # Separate successes and failures
    {successes, failures} = Enum.split_with(results, fn r -> r["status"] == "spawned" end)

    spawned_job_ids =
      successes
      |> Enum.map(& &1["job_id"])
      |> Enum.reject(&is_nil/1)

    %{
      total_cities: length(cities),
      cities_processed: length(successes),
      cities_failed: length(failures),
      jobs_spawned: length(spawned_job_ids),
      spawned_job_ids: spawned_job_ids,
      city_results: successes,
      failed_cities: failures
    }
  end

  defp spawn_city_job(city, force) do
    Logger.info("  📍 Spawning job for #{city.name} (#{city.venue_count} venues)")

    # Use limit: -1 for unlimited processing
    case TriviaAdvisorBackfillJob.enqueue(
           city_id: city.id,
           limit: -1,
           force: force
         ) do
      {:ok, job} ->
        Logger.info("    ✅ Spawned job ##{job.id} for #{city.name}")

        %{
          "city_id" => city.id,
          "city_name" => city.name,
          "venue_count" => city.venue_count,
          "job_id" => job.id,
          "status" => "spawned"
        }

      {:error, reason} ->
        Logger.error("    ❌ Failed to spawn job for #{city.name}: #{inspect(reason)}")

        %{
          "city_id" => city.id,
          "city_name" => city.name,
          "venue_count" => city.venue_count,
          "job_id" => nil,
          "status" => "failed",
          "error" => inspect(reason)
        }
    end
  end

  defp store_success_meta(job, results, dry_run) do
    status =
      cond do
        dry_run -> "dry_run_completed"
        results.cities_failed == 0 -> "completed"
        results.cities_processed > 0 -> "partial_success"
        true -> "failed"
      end

    meta = %{
      "status" => status,
      "dry_run" => dry_run,
      "total_cities" => results.total_cities,
      "cities_processed" => results.cities_processed,
      "cities_failed" => results.cities_failed,
      "jobs_spawned" => results.jobs_spawned,
      "spawned_job_ids" => results.spawned_job_ids,
      "city_results" => results.city_results,
      "failed_cities" => results.failed_cities,
      "processed_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
    }

    case Oban.update_job(job, %{meta: meta}) do
      {:ok, _} ->
        Logger.debug("✅ Stored results in Oban meta for job #{job.id}")

      {:error, reason} ->
        Logger.error("❌ Failed to store results in Oban meta: #{inspect(reason)}")
    end
  end

  defp store_failure_meta(job, meta_data) do
    meta =
      meta_data
      |> Map.put("processed_at", NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601())

    case Oban.update_job(job, %{meta: meta}) do
      {:ok, _} ->
        Logger.debug("✅ Stored failure info in Oban meta for job #{job.id}")

      {:error, reason} ->
        Logger.error("❌ Failed to store failure info in Oban meta: #{inspect(reason)}")
    end
  end

  defp convert_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
