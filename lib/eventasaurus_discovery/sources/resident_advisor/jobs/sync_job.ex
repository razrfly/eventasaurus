defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.SyncJob do
  @moduledoc """
  Oban job for syncing Resident Advisor events via GraphQL API.

  Unlike HTML scrapers, RA uses a GraphQL API which provides structured data:
  1. SyncJob queries GraphQL with pagination
  2. Transforms events to unified format
  3. Filters events using EventFreshnessChecker (skips recently seen events)
  4. Schedules EventDetailJob for stale events only
  5. Uses unified Processor for venue/event creation

  ## Job Arguments

  - `source_id` - Database ID of the RA source
  - `city_id` - Database ID of the target city
  - `area_id` - RA integer area ID (see AreaMapper)
  - `start_date` - ISO date string (default: today)
  - `end_date` - ISO date string (default: today + 30 days)
  - `page_size` - Results per page (default: 20, max: 100)

  ## Features

  - GraphQL pagination with cursor support
  - Freshness-based filtering (skips events updated within threshold)
  - EventDetailJob for processing individual events
  - Multi-strategy venue geocoding
  - Strict venue validation (rejects events without coordinates)
  - Rate limiting (2 req/s default)
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.Source

  alias EventasaurusDiscovery.Sources.ResidentAdvisor.{
    Client,
    Config,
    Transformer,
    ContainerGrouper,
    Jobs.EventDetailJob
  }

  alias EventasaurusDiscovery.PublicEvents.PublicEventContainers
  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # BaseJob callbacks - not used for GraphQL API pagination
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # Resident Advisor uses GraphQL API pagination instead of city-based fetch
    Logger.warning("⚠️ fetch_events called on GraphQL API source - not used")
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Resident Advisor transformation happens in EventDetailJob
    Logger.debug("🔄 transform_events called (not used in GraphQL API pattern)")
    raw_events
  end

  @doc """
  Source configuration for BaseJob.
  """
  def source_config do
    %{
      name: "Resident Advisor",
      slug: "resident-advisor",
      website_url: "https://ra.co",
      priority: 75,
      domains: ["music", "electronic", "nightlife"],
      aggregate_on_index: false,
      aggregation_type: nil,
      config: %{
        "rate_limit_seconds" => Config.rate_limit(),
        "max_requests_per_hour" => 7200,
        "api_type" => "graphql",
        "supports_pagination" => true,
        "discovery_method" => "graphql_pagination"
      }
    }
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    # Debug: Log the args to see what we receive
    Logger.debug("RA SyncJob received args: #{inspect(args)}")

    # Extract area_id from options if provided (dashboard integration)
    area_id_from_args = args["area_id"] || get_in(args, ["options", "area_id"])
    Logger.debug("Extracted area_id: #{inspect(area_id_from_args)}")

    # Validate required arguments
    with {:ok, city_id} <- validate_integer(args["city_id"], "city_id"),
         {:ok, area_id} <- validate_integer(area_id_from_args, "area_id") do
      # Generate external_id for tracking
      external_id = "resident_advisor_sync_city_#{city_id}_#{Date.utc_today()}"

      # Optional arguments with defaults
      start_date = args["start_date"] || default_start_date()
      end_date = args["end_date"] || default_end_date()
      page_size = args["page_size"] || 20
      force = args["force"] || false

      if force do
        Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
      end

      Logger.info("""
      🎵 Starting Resident Advisor sync
      City ID: #{city_id}
      Area ID: #{area_id}
      Date range: #{start_date} to #{end_date}
      Page size: #{page_size}
      """)

      # Get city with country preloaded
      case JobRepo.get(City, city_id) do
        nil ->
          error_msg = "City not found: #{city_id}"
          Logger.error(error_msg)
          MetricsTracker.record_failure(job, error_msg, external_id)
          {:error, :city_not_found}

        city ->
          city = JobRepo.preload(city, :country)
          source = get_or_create_ra_source()

          case sync_events(city, area_id, start_date, end_date, page_size, source, force) do
            {:ok, result} ->
              MetricsTracker.record_success(job, external_id)
              {:ok, result}

            {:error, reason} = error ->
              MetricsTracker.record_failure(job, "Sync failed: #{inspect(reason)}", external_id)
              error
          end
      end
    else
      {:error, field, reason} ->
        error_msg = "Invalid job arguments - #{field}: #{reason}"
        Logger.error("❌ #{error_msg}")
        # Generate fallback external_id for error tracking
        external_id = "resident_advisor_sync_error_#{Date.utc_today()}"
        MetricsTracker.record_failure(job, error_msg, external_id)
        {:error, "invalid_args_#{field}"}
    end
  end

  # Private functions

  defp sync_events(city, area_id, start_date, end_date, page_size, source, force) do
    Logger.info("🚀 Fetching RA events for #{city.name} (area #{area_id})")

    # GraphQL pagination state
    result =
      fetch_all_pages(
        area_id,
        start_date,
        end_date,
        page_size,
        _page = 1,
        _accumulated_events = []
      )

    case result do
      {:ok, all_events} ->
        Logger.info("📚 Fetched #{length(all_events)} events from RA GraphQL")

        # Transform events and queue individual processing jobs
        {queued_count, failed_count} = schedule_event_detail_jobs(all_events, city, source, force)

        Logger.info("""
        ✅ RA sync completed
        Total events fetched: #{length(all_events)}
        EventDetailJobs queued: #{queued_count}
        Failed validation: #{failed_count}
        """)

        {:ok,
         %{
           events_fetched: length(all_events),
           jobs_queued: queued_count,
           validation_failures: failed_count
         }}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch RA events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_all_pages(area_id, start_date, end_date, page_size, page, accumulated) do
    # Rate limiting
    if page > 1 do
      # Sleep between requests (2 req/s = 500ms delay)
      Process.sleep(div(1000, Config.rate_limit()))
    end

    Logger.debug("📄 Fetching RA page #{page} (#{length(accumulated)} events so far)")

    case Client.fetch_events(area_id, start_date, end_date, page, page_size) do
      {:ok, %{"eventListings" => %{"data" => events}}} when is_list(events) ->
        # Append new events
        all_events = accumulated ++ events

        # Check if we should continue pagination
        if length(events) >= page_size do
          # More pages likely available
          Logger.debug("🔄 Page #{page} has #{length(events)} events, fetching next page")
          fetch_all_pages(area_id, start_date, end_date, page_size, page + 1, all_events)
        else
          # Last page or empty page
          Logger.info("📭 Reached last page (#{page}), total events: #{length(all_events)}")
          {:ok, all_events}
        end

      {:ok, unexpected} ->
        Logger.warning("⚠️ Unexpected GraphQL response structure: #{inspect(unexpected)}")
        {:ok, accumulated}

      {:error, :rate_limited} ->
        Logger.warning("⚠️ Rate limited on page #{page}, waiting and retrying...")
        Process.sleep(5000)
        fetch_all_pages(area_id, start_date, end_date, page_size, page, accumulated)

      {:error, reason} ->
        Logger.error("❌ GraphQL query failed on page #{page}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule_event_detail_jobs(raw_events, city, source, force) do
    # PHASE 1: Use ContainerGrouper to detect and create festival containers
    Logger.info("🔍 Running multi-signal container detection...")

    container_groups = ContainerGrouper.group_events_into_containers(raw_events)

    Logger.info("📦 Detected #{length(container_groups)} festival container(s)")

    # Create containers from grouped data
    Enum.each(container_groups, fn container_data ->
      case PublicEventContainers.create_from_festival_group(container_data, source.id) do
        {:ok, container} ->
          Logger.info("""
          ✅ Festival container created: #{container.title}
          Promoter: #{container_data[:promoter_name]} (ID: #{container_data[:promoter_id]})
          Sub-events detected: #{length(container_data[:sub_events])}
          """)

        {:error, changeset} ->
          Logger.error("❌ Failed to create festival container: #{inspect(changeset.errors)}")
      end
    end)

    # PHASE 2: Transform events and filter for freshness before scheduling
    Logger.info("🔍 Transforming #{length(raw_events)} raw events...")

    # Transform all events first
    transformed_events =
      raw_events
      |> Enum.map(fn raw_event ->
        case Transformer.transform_event(raw_event, city) do
          {:ok, transformed} -> {:ok, transformed}
          {:umbrella, _umbrella_data} -> :skip_umbrella
          {:error, reason} -> {:error, reason, raw_event}
        end
      end)

    # Extract successfully transformed events for freshness check
    transformed_for_check =
      transformed_events
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, event} -> event end)

    # Apply freshness filter (unless force=true)
    events_to_process =
      if force do
        transformed_for_check
      else
        EventFreshnessChecker.filter_events_needing_processing(
          transformed_for_check,
          source.id
        )
      end

    # Log efficiency metrics
    total_transformed = length(transformed_for_check)
    skipped = total_transformed - length(events_to_process)
    threshold = EventFreshnessChecker.get_threshold()

    Logger.info("""
    🔄 Resident Advisor Freshness Check
    Processing #{length(events_to_process)}/#{total_transformed} events #{if force, do: "(Force mode)", else: "(#{skipped} fresh, threshold: #{threshold}h)"}
    """)

    # Create a set of external_ids to process for fast lookup
    ids_to_process = MapSet.new(events_to_process, & &1[:external_id])

    # PHASE 3: Queue only stale events for processing
    {queued, failed} =
      transformed_events
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {result, index}, {queued_acc, failed_acc} ->
        case result do
          :skip_umbrella ->
            # Skip umbrella events - containers already created by ContainerGrouper
            {queued_acc, failed_acc}

          {:ok, transformed} ->
            # Check if event passed freshness filter
            if MapSet.member?(ids_to_process, transformed[:external_id]) do
              # Event is stale - queue for processing
              # Stagger jobs to avoid overwhelming the system (Config.rate_limit() seconds apart)
              delay_seconds = index * Config.rate_limit()

              job_args = %{
                "event_data" => transformed,
                "source_id" => source.id
              }

              case EventDetailJob.new(job_args, schedule_in: delay_seconds) |> Oban.insert() do
                {:ok, _job} ->
                  {[transformed[:external_id] | queued_acc], failed_acc}

                {:error, reason} ->
                  Logger.warning(
                    "⚠️ Failed to queue EventDetailJob for #{transformed[:external_id]}: #{inspect(reason)}"
                  )

                  {queued_acc, [transformed[:external_id] | failed_acc]}
              end
            else
              # Event is fresh - skip scheduling
              Logger.debug("⏭️ Skipping fresh event #{transformed[:external_id]}")
              {queued_acc, failed_acc}
            end

          {:error, reason, raw_event} ->
            external_id = get_in(raw_event, ["event", "id"]) || "unknown"

            Logger.warning("""
            ⚠️ Failed to transform RA event (venue validation failed)
            Event ID: #{external_id}
            Reason: #{inspect(reason)}
            """)

            {queued_acc, [external_id | failed_acc]}
        end
      end)

    {length(queued), length(failed)}
  end

  # Validation helpers

  defp validate_integer(nil, field), do: {:error, field, "is required"}
  defp validate_integer(value, _field) when is_integer(value), do: {:ok, value}

  defp validate_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, field, "invalid integer: #{inspect(value)}"}
    end
  end

  defp validate_integer(value, field),
    do: {:error, field, "expected integer, got: #{inspect(value)}"}

  defp default_start_date do
    Date.utc_today()
    |> Date.to_iso8601()
  end

  defp default_end_date do
    Date.utc_today()
    |> Date.add(60)
    |> Date.to_iso8601()
  end

  defp get_or_create_ra_source do
    case JobRepo.get_by(Source, slug: "resident-advisor") do
      nil ->
        Logger.warning("⚠️ RA source not found, creating from config")

        %Source{}
        |> Source.changeset(%{
          name: "Resident Advisor",
          slug: "resident-advisor",
          website_url: "https://ra.co",
          priority: 75,
          metadata: %{
            "rate_limit_seconds" => 0.5,
            "max_requests_per_hour" => 7200,
            "api_type" => "graphql",
            "supports_pagination" => true
          }
        })
        |> JobRepo.insert!()

      source ->
        source
    end
  end
end
