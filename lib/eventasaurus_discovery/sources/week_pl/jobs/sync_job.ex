defmodule EventasaurusDiscovery.Sources.WeekPl.Jobs.SyncJob do
  @moduledoc """
  Festival-aware orchestration job for week.pl integration.

  ## Responsibilities
  - Check if any festival is currently active
  - Queue RegionSyncJob for each supported city if festival active
  - Skip processing entirely if no festival active (saves API calls)

  ## Festival Logic
  - Checks active_festivals() for current date
  - Only runs during RestaurantWeek, FineDiningWeek, BreakfastWeek periods
  - Festivals defined in Source module (update annually)

  ## Job Structure
  - Parent: This job (festival check)
  - Children: 13 RegionSyncJob (one per city)
  - Grandchildren: RestaurantDetailJob (one per restaurant)
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3,
    priority: 1

  require Logger
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Sources.Source, as: SourceSchema
  alias EventasaurusDiscovery.Sources.WeekPl.{Source, Client, DeploymentConfig, FestivalManager}
  alias EventasaurusDiscovery.Sources.WeekPl.Jobs.RegionSyncJob
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # BaseJob callbacks - not used for festival-based orchestration
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # Week.pl uses festival-based orchestration instead of direct city-based fetch
    Logger.warning("⚠️ fetch_events called on festival-based source - not used")
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Week.pl uses festival-based orchestration, transformation happens in detail jobs
    Logger.debug("🔄 transform_events called (not used in orchestration pattern)")
    raw_events
  end

  @doc """
  Source configuration for BaseJob.
  """
  def source_config do
    %{
      name: Source.name(),
      slug: Source.key(),
      website_url: "https://week.pl",
      priority: Source.priority(),
      domains: ["food", "dining"],
      aggregate_on_index: true,
      aggregation_type: "FoodEvent",
      config: %{
        "rate_limit_seconds" => 2,
        "max_requests_per_hour" => 1800,
        "language" => "pl",
        "scope" => "regional",
        "coverage" => "13 Polish cities",
        "requires_geocoding" => false,
        "has_coordinates" => true,
        "discovery_method" => "festival_orchestration"
      }
    }
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "week_pl_sync_#{Date.utc_today()}"
    Logger.info("🍽️  [WeekPl.SyncJob] Starting festival check...")

    # Get or create source record
    source = get_or_create_week_pl_source()
    limit = args["limit"]
    force = args["force"] || false

    if force do
      Logger.info("⚡ Force mode enabled - bypassing festival check")
    end

    # Check deployment status
    unless DeploymentConfig.enabled?() do
      Logger.info("⏭️  [WeekPl.SyncJob] Source disabled via deployment config")
      MetricsTracker.record_success(job, external_id)

      {:ok,
       %{
         "job_role" => "sync_orchestrator",
         "pipeline_id" => "week_pl_#{Date.utc_today()}",
         "status" => "skipped",
         "reason" => "source_disabled",
         "source" => "week_pl",
         "deployment_phase" => to_string(DeploymentConfig.deployment_phase())
       }}
    else
      execute_sync(source.id, limit, force, job.id, external_id, job)
    end
  end

  defp execute_sync(source_id, limit, force, parent_job_id, external_id, job) do
    pipeline_id = "week_pl_#{Date.utc_today()}"

    deployment_status = DeploymentConfig.status()

    Logger.info(
      "📊 [WeekPl.SyncJob] Deployment: #{deployment_status.phase}, #{deployment_status.active_cities} cities active"
    )

    # Check if any festival is currently active (or force mode)
    if Source.festival_active?() || force do
      if force && !Source.festival_active?() do
        Logger.info("⚡ Force mode: bypassing festival check (no active festival)")
      else
        Logger.info("✅ [WeekPl.SyncJob] Festival is active, queuing region jobs...")
      end

      # Get current active festival for metadata (or use first festival if forcing)
      active_festival = get_active_festival() || get_fallback_festival()

      # Queue job for each enabled city (respects deployment phase)
      cities = DeploymentConfig.active_cities()
      cities_to_process = if limit, do: Enum.take(cities, limit), else: cities

      results =
        cities_to_process
        |> Enum.map(fn city ->
          queue_region_job(source_id, city, active_festival, force, parent_job_id, pipeline_id)
        end)

      # Check if all jobs queued successfully
      failed = Enum.filter(results, fn {status, _} -> status == :error end)

      if Enum.empty?(failed) do
        Logger.info(
          "✅ [WeekPl.SyncJob] Queued #{length(results)} region jobs for active festival"
        )

        MetricsTracker.record_success(job, external_id)

        {:ok,
         %{
           "job_role" => "sync_orchestrator",
           "pipeline_id" => pipeline_id,
           "status" => "success",
           "jobs_queued" => length(results),
           "festival" => active_festival.code,
           "source" => "week_pl",
           "cities" => Enum.map(cities_to_process, & &1.name)
         }}
      else
        Logger.error("❌ [WeekPl.SyncJob] Failed to queue #{length(failed)} region jobs")

        # Use standard category for ErrorCategories.categorize_error/1
        # See docs/error-handling-guide.md for category definitions
        MetricsTracker.record_failure(job, :dependency_error, external_id)

        {:error, "Failed to queue some region jobs"}
      end
    else
      Logger.info("⏭️  [WeekPl.SyncJob] No active festival, skipping sync")
      MetricsTracker.record_success(job, external_id)

      next_festival = get_next_festival()

      next_festival_data =
        if next_festival,
          do: %{"code" => next_festival.code, "starts_at" => to_string(next_festival.starts_at)},
          else: nil

      {:ok,
       %{
         "job_role" => "sync_orchestrator",
         "pipeline_id" => pipeline_id,
         "status" => "skipped",
         "reason" => "no_active_festival",
         "source" => "week_pl",
         "next_festival" => next_festival_data
       }}
    end
  end

  # Get currently active festival from API
  defp get_active_festival do
    case Client.fetch_festival_editions() do
      {:ok, [edition | _]} ->
        # API returned festivals - transform first one to our format
        transform_api_festival(edition)

      {:ok, []} ->
        # No ongoing festivals from API
        nil

      {:error, reason} ->
        Logger.warning("[WeekPl.SyncJob] API fetch failed (#{inspect(reason)}), using fallback")
        # API failed - check fallback festivals
        today = Date.utc_today()

        Source.fallback_festivals()
        |> Enum.find(fn festival ->
          Date.compare(today, festival.starts_at) in [:eq, :gt] and
            Date.compare(today, festival.ends_at) in [:eq, :lt]
        end)
    end
  end

  # Get fallback festival (used when forcing or API unavailable)
  defp get_fallback_festival do
    List.first(Source.fallback_festivals())
  end

  # Get next upcoming festival
  defp get_next_festival do
    case Client.fetch_festival_editions() do
      {:ok, editions} when editions != [] ->
        # API returned festivals - find the next upcoming one
        today = Date.utc_today()

        editions
        |> Enum.map(&transform_api_festival/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(fn festival ->
          Date.compare(today, festival.starts_at) == :lt
        end)
        |> Enum.sort_by(& &1.starts_at, Date)
        |> List.first()
        |> case do
          nil -> nil
          festival -> %{code: festival.code, starts_at: festival.starts_at}
        end

      {:ok, []} ->
        # No festivals from API - check fallback
        check_fallback_next_festival()

      {:error, _reason} ->
        # API failed - check fallback
        check_fallback_next_festival()
    end
  end

  defp check_fallback_next_festival do
    today = Date.utc_today()

    Source.fallback_festivals()
    |> Enum.filter(fn festival ->
      Date.compare(today, festival.starts_at) == :lt
    end)
    |> Enum.sort_by(& &1.starts_at, Date)
    |> List.first()
    |> case do
      nil -> nil
      festival -> %{code: festival.code, starts_at: festival.starts_at}
    end
  end

  # Transform API festival edition to our internal format
  defp transform_api_festival(edition) do
    # API returns datetime strings with timezone (e.g., "2026-03-04T00:00:00+01:00")
    # Parse as DateTime first, then convert to Date with error handling
    with {:ok, starts_at_dt, _} <- DateTime.from_iso8601(edition["startsAt"]),
         {:ok, ends_at_dt, _} <- DateTime.from_iso8601(edition["endsAt"]) do
      %{
        name: edition["festival"]["name"],
        code: edition["code"],
        starts_at: DateTime.to_date(starts_at_dt),
        ends_at: DateTime.to_date(ends_at_dt),
        price: edition["price"]
      }
    else
      {:error, reason} ->
        Logger.error(
          "[WeekPl.SyncJob] Invalid date format in festival edition: #{inspect(edition)}, reason: #{inspect(reason)}"
        )

        nil
    end
  end

  # Queue region sync job for a city
  defp queue_region_job(source_id, city, festival, force, parent_job_id, pipeline_id) do
    # Create or get festival container for this city (Phase 4: #2334)
    case FestivalManager.get_or_create_festival_container(
           source_id,
           festival,
           city.name,
           city.country
         ) do
      {:ok, container} ->
        args = %{
          "source_id" => source_id,
          "region_id" => city.id,
          "region_name" => city.name,
          "country" => city.country,
          "festival_code" => festival.code,
          "festival_name" => festival.name,
          "festival_price" => festival.price,
          # Phase 4: Pass container ID to child jobs
          "festival_container_id" => container.id,
          "force" => force
        }

        meta = %{
          parent_job_id: parent_job_id,
          pipeline_id: pipeline_id,
          entity_id: city.id,
          entity_type: "region"
        }

        case Oban.insert(RegionSyncJob.new(args, meta: meta)) do
          {:ok, _job} ->
            Logger.debug(
              "✅ Queued RegionSyncJob for #{city.name} with festival container #{container.id}"
            )

            {:ok, city.name}

          {:error, reason} ->
            Logger.error("❌ Failed to queue RegionSyncJob for #{city.name}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to create festival container for #{city.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Get or create week.pl source record
  defp get_or_create_week_pl_source do
    case JobRepo.get_by(SourceSchema, slug: Source.key()) do
      nil ->
        Logger.info("Creating week.pl source record...")

        %SourceSchema{}
        |> SourceSchema.changeset(%{
          name: Source.name(),
          slug: Source.key(),
          website_url: "https://week.pl",
          priority: Source.priority(),
          metadata: %{
            "rate_limit_seconds" => 2,
            "max_requests_per_hour" => 1800,
            "language" => "pl",
            "scope" => "regional",
            "coverage" => "13 Polish cities",
            "requires_geocoding" => false,
            "has_coordinates" => true
          }
        })
        |> JobRepo.insert!()

      source ->
        source
    end
  end
end
