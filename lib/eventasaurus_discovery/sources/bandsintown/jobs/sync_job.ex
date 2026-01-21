defmodule EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob do
  @moduledoc """
  Unified Oban job for syncing BandsInTown events.

  Uses the standardized BaseJob behaviour for consistent processing across all sources.
  All events are processed through the unified Processor which enforces venue requirements.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Metrics.MetricsTracker
  alias EventasaurusDiscovery.Sources.Bandsintown.{Client, Config, Transformer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    city_id = args["city_id"]
    limit = args["limit"] || 200
    max_pages = args["max_pages"] || calculate_max_pages(limit)
    force = args["force"] || false
    external_id = "bandsintown_sync_city_#{city_id}_#{Date.utc_today()}"

    # Get city
    case JobRepo.get(EventasaurusDiscovery.Locations.City, city_id) do
      nil ->
        error_msg = "City not found: #{inspect(city_id)}"
        Logger.error(error_msg)
        MetricsTracker.record_failure(job, error_msg, external_id)
        {:error, :city_not_found}

      city ->
        city = JobRepo.preload(city, :country)

        if force do
          Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
        end

        Logger.info("""
        🎵 Starting Bandsintown async sync
        City: #{city.name}, #{city.country.name}
        Limit: #{limit} events
        Max pages: #{max_pages}
        """)

        result =
          schedule_async_sync(city,
            source: get_or_create_bandsintown_source(),
            limit: limit,
            max_pages: max_pages,
            force: force
          )

        # Schedule coordinate recalculation after successful sync
        case result do
          {:ok, _stats} = success ->
            schedule_coordinate_update(city_id)
            Logger.info("🗺️ Scheduled coordinate update for city #{city_id}")
            MetricsTracker.record_success(job, external_id)
            success

          {:error, reason} = error ->
            MetricsTracker.record_failure(job, "Sync failed: #{inspect(reason)}", external_id)
            error
        end
    end
  end

  defp schedule_async_sync(city, opts) do
    source = opts[:source]
    limit = opts[:limit]
    max_pages = opts[:max_pages]
    force = opts[:force] || false

    Logger.info("🚀 Starting asynchronous Bandsintown sync")

    # Get city coordinates
    latitude = Decimal.to_float(city.latitude)
    longitude = Decimal.to_float(city.longitude)

    # Determine how many pages to schedule
    # For Bandsintown, we can probe the API to see how many pages have data
    case determine_page_count(latitude, longitude, max_pages) do
      {:ok, total_pages} when total_pages > 0 ->
        Logger.info("📚 Found #{total_pages} API pages to process")

        # Calculate how many pages we actually need for the limit
        pages_to_schedule =
          if limit do
            pages_needed = calculate_max_pages(limit)
            min(total_pages, pages_needed)
          else
            total_pages
          end

        Logger.info("📋 Scheduling #{pages_to_schedule} pages (limit: #{limit || "none"})")

        # Schedule IndexPageJobs for each page
        scheduled_count =
          schedule_index_page_jobs(
            pages_to_schedule,
            latitude,
            longitude,
            source.id,
            city.id,
            city.name,
            limit,
            force
          )

        Logger.info("""
        ✅ Bandsintown sync job completed (asynchronous mode)
        Total pages available: #{total_pages}
        Pages scheduled: #{pages_to_schedule}
        Index page jobs scheduled: #{scheduled_count}
        Events will be processed asynchronously
        """)

        {:ok,
         %{
           pages_found: total_pages,
           pages_scheduled: pages_to_schedule,
           jobs_scheduled: scheduled_count,
           mode: "asynchronous"
         }}

      {:ok, 0} ->
        Logger.warning("⚠️ No pages found to process")
        {:ok, %{pages_found: 0, jobs_scheduled: 0}}

      {:error, reason} ->
        Logger.error("❌ Failed to determine page count: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp determine_page_count(latitude, longitude, max_pages) do
    Logger.info("🔍 Determining total page count (max: #{max_pages || "unlimited"})")

    # Quick scan to determine how many pages have events
    scan_pages_for_count(latitude, longitude, 1, max_pages, 0)
  end

  defp scan_pages_for_count(_latitude, _longitude, current_page, max_pages, _last_valid)
       when is_integer(max_pages) and current_page > max_pages do
    {:ok, max_pages}
  end

  defp scan_pages_for_count(latitude, longitude, current_page, max_pages, last_valid) do
    # Check if this page has events
    case Client.fetch_next_events_page(latitude, longitude, current_page) do
      {:ok, json_data} when is_map(json_data) ->
        # Check if we got events
        events = extract_events_from_response(json_data)

        if length(events) > 0 do
          Logger.debug("✅ Page #{current_page} has #{length(events)} events")
          scan_pages_for_count(latitude, longitude, current_page + 1, max_pages, current_page)
        else
          Logger.info("📭 No events on page #{current_page}, total pages: #{last_valid}")
          {:ok, last_valid}
        end

      {:ok, ""} ->
        # Empty string response - treat as no events
        Logger.info("📭 Empty response on page #{current_page}, total pages: #{last_valid}")
        {:ok, last_valid}

      {:ok, _other} ->
        # Non-map, non-empty response - treat as no events
        Logger.warning(
          "⚠️ Unexpected response format on page #{current_page}, total pages: #{last_valid}"
        )

        {:ok, last_valid}

      {:error, {:http_error, 404}} ->
        Logger.info("📭 Page #{current_page} not found, total pages: #{last_valid}")
        {:ok, last_valid}

      {:error, reason} ->
        if last_valid > 0 do
          Logger.warning("⚠️ Error scanning page #{current_page}, using last valid: #{last_valid}")
          {:ok, last_valid}
        else
          {:error, reason}
        end
    end
  end

  defp extract_events_from_response(json_data) do
    case json_data do
      %{"events" => events} when is_list(events) -> events
      %{"data" => %{"events" => events}} when is_list(events) -> events
      _ -> []
    end
  end

  defp schedule_index_page_jobs(
         total_pages,
         latitude,
         longitude,
         source_id,
         city_id,
         city_name,
         limit,
         force
       ) do
    Logger.info("📅 Scheduling #{total_pages} index page jobs")

    # Schedule IndexPageJobs for each page
    scheduled_jobs =
      1..total_pages
      |> Enum.map(fn page_num ->
        # Stagger the jobs slightly to avoid thundering herd
        # But allow some concurrency (pages can be processed in parallel)
        # 3 seconds rate limit
        delay_seconds = div(page_num - 1, 3) * 3

        job_args = %{
          "page_number" => page_num,
          "latitude" => latitude,
          "longitude" => longitude,
          "source_id" => source_id,
          "city_id" => city_id,
          "city_name" => city_name,
          "limit" => if(page_num == 1, do: limit, else: nil),
          "total_pages" => total_pages,
          "force" => force
        }

        EventasaurusDiscovery.Sources.Bandsintown.Jobs.IndexPageJob.new(
          job_args,
          queue: :scraper_index,
          schedule_in: delay_seconds
        )
        |> Oban.insert()
      end)

    # Count successful insertions
    successful_count =
      Enum.count(scheduled_jobs, fn
        {:ok, _} -> true
        _ -> false
      end)

    Logger.info("✅ Successfully scheduled #{successful_count}/#{total_pages} index page jobs")
    successful_count
  end

  defp get_or_create_bandsintown_source do
    case JobRepo.get_by(Source, slug: "bandsintown") do
      nil ->
        config = source_config()

        %Source{}
        |> Source.changeset(config)
        |> JobRepo.insert!()

      source ->
        source
    end
  end

  # Keep the original fetch_events for compatibility with BaseJob if needed
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, _options) do
    Logger.info("""
    🎵 Fetching Bandsintown events (inline mode - deprecated)
    City: #{city.name}, #{city.country.name}
    Target events: #{limit}
    """)

    # This method is kept for backward compatibility but should not be used
    # The async architecture is now preferred
    {:error, :use_async_mode}
  end

  # Keep @impl on the 1-arity variant to satisfy BaseJob behaviour
  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    transform_events(raw_events, %{})
  end

  def transform_events(raw_events, options) do
    # Extract city context from options (passed by BaseJob)
    city = options["city"]

    # Transform each event using our Transformer
    # Filter out events that fail venue validation
    raw_events
    |> Enum.map(&Transformer.transform_event(&1, city))
    |> Enum.filter(fn
      {:ok, _event} -> true
      {:error, _reason} -> false
    end)
    |> Enum.map(fn {:ok, event} -> event end)
  end

  # Required by BaseJob for source configuration
  def source_config do
    Config.source_config()
  end

  # Private helper functions

  defp calculate_max_pages(limit) do
    # Estimate pages based on ~20 events per page
    pages = div(limit, 20)
    if rem(limit, 20) > 0, do: pages + 1, else: pages
  end
end
