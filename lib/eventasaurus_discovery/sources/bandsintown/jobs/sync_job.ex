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

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.Bandsintown.{Config, Transformer}
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_id = args["city_id"]
    limit = args["limit"] || 200
    max_pages = args["max_pages"] || calculate_max_pages(limit)

    # Get city
    case Repo.get(EventasaurusDiscovery.Locations.City, city_id) do
      nil ->
        Logger.error("City not found: #{inspect(city_id)}")
        {:error, :city_not_found}

      city ->
        city = Repo.preload(city, :country)

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
            max_pages: max_pages
          )

        # Schedule coordinate recalculation after successful sync
        case result do
          {:ok, _} = success ->
            schedule_coordinate_update(city_id)
            Logger.info("🗺️ Scheduled coordinate update for city #{city_id}")
            success

          other ->
            other
        end
    end
  end

  defp schedule_async_sync(city, opts) do
    source = opts[:source]
    limit = opts[:limit]
    max_pages = opts[:max_pages]

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
            limit
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
         limit
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
        scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

        job_args = %{
          "page_number" => page_num,
          "latitude" => latitude,
          "longitude" => longitude,
          "source_id" => source_id,
          "city_id" => city_id,
          "city_name" => city_name,
          "limit" => if(page_num == 1, do: limit, else: nil),
          "total_pages" => total_pages
        }

        EventasaurusDiscovery.Sources.Bandsintown.Jobs.IndexPageJob.new(
          job_args,
          queue: :scraper_index,
          scheduled_at: scheduled_at
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
    case Repo.get_by(Source, slug: "bandsintown") do
      nil ->
        config = source_config()

        %Source{}
        |> Source.changeset(config)
        |> Repo.insert!()

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
