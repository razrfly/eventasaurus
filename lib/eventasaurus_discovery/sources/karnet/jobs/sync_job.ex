defmodule EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob do
  @moduledoc """
  Unified Oban job for syncing Karnet Kraków events.

  Uses the standardized BaseJob behaviour for consistent processing across all sources.
  All events are processed through the unified Processor which enforces venue requirements.

  Implements chunked processing to avoid timeouts with large event limits.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  # Process events in chunks to avoid timeouts
  @chunk_size 100

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.Karnet.{Client, Config, IndexExtractor, DetailExtractor, Transformer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"limit" => limit} = args}) when limit > @chunk_size and not is_map_key(args, "chunk") do
    # Large sync request - break into chunks
    city_id = args["city_id"]

    Logger.info("""
    📦 Breaking large Karnet sync into chunks
    Total limit: #{limit} events
    Chunk size: #{@chunk_size} events
    """)

    # Calculate number of chunks needed
    chunks = div(limit, @chunk_size) + if(rem(limit, @chunk_size) > 0, do: 1, else: 0)

    # Schedule chunked jobs
    scheduled_jobs = Enum.map(0..(chunks - 1), fn chunk_idx ->
      chunk_limit = if chunk_idx == chunks - 1 do
        # Last chunk might be smaller
        remaining = rem(limit, @chunk_size)
        if remaining > 0, do: remaining, else: @chunk_size
      else
        @chunk_size
      end

      chunk_args = %{
        "city_id" => city_id,
        "limit" => chunk_limit,
        "chunk" => chunk_idx + 1,
        "total_chunks" => chunks,
        "original_limit" => limit,
        "chunk_offset" => chunk_idx * @chunk_size
      }

      # Stagger chunks by 30 seconds to avoid overwhelming the source
      schedule_at = DateTime.add(DateTime.utc_now(), chunk_idx * 30, :second)

      __MODULE__.new(chunk_args, scheduled_at: schedule_at)
      |> Oban.insert()
    end)

    successful_count = Enum.count(scheduled_jobs, fn
      {:ok, _} -> true
      _ -> false
    end)

    Logger.info("✅ Scheduled #{successful_count}/#{chunks} chunk jobs for Karnet sync")

    {:ok, %{
      mode: "chunked",
      chunks_scheduled: successful_count,
      total_chunks: chunks,
      chunk_size: @chunk_size
    }}
  end

  def perform(%Oban.Job{args: args}) do
    # Regular sync or chunk processing
    city_id = args["city_id"]
    limit = args["limit"] || 200
    max_pages = args["max_pages"] || calculate_max_pages(limit)

    # Log if this is a chunk
    if args["chunk"] do
      Logger.info("""
      🧩 Processing Karnet sync chunk #{args["chunk"]}/#{args["total_chunks"]}
      Chunk limit: #{limit} events
      Offset: #{args["chunk_offset"] || 0}
      """)
    end

    # Get city (should be Kraków)
    case Repo.get(City, city_id) do
      nil ->
        Logger.error("City not found: #{inspect(city_id)}")
        {:error, :city_not_found}

      city ->
        city = Repo.preload(city, :country)

        # Verify it's Kraków (or allow other Polish cities in the future)
        unless String.downcase(city.name) in ["kraków", "krakow", "cracow"] do
          Logger.warning("⚠️ Karnet scraper is designed for Kraków but got: #{city.name}")
        end

        Logger.info("""
        🎭 Starting Karnet Kraków inline sync
        City: #{city.name}, #{city.country.name}
        Limit: #{limit} events
        Max pages: #{max_pages}
        """)

        result = continue_sync(city,
          source: get_or_create_karnet_source(),
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


  defp continue_sync(_city, opts) do
    source = opts[:source]
    limit = opts[:limit]
    max_pages = opts[:max_pages]

    # For chunks, use optimistic page discovery to avoid timeout
    Logger.info("🚀 Starting Karnet sync (limit: #{limit}, max_pages: #{max_pages})")

    # For smaller limits, we can still do page discovery
    # For larger limits or chunks, use optimistic approach
    if limit <= @chunk_size do
      # Small sync - do normal page discovery
      case determine_page_count(max_pages) do
      {:ok, total_pages} when total_pages > 0 ->
        Logger.info("📚 Found #{total_pages} index pages to process")

        # Calculate how many pages we actually need for the limit
        pages_to_schedule = if limit do
          pages_needed = calculate_max_pages(limit)
          min(total_pages, pages_needed)
        else
          total_pages
        end

        Logger.info("📋 Scheduling #{pages_to_schedule} pages (limit: #{limit || "none"})")

        # Schedule IndexPageJobs for each page
        scheduled_count = schedule_index_page_jobs(pages_to_schedule, source.id, limit)

        Logger.info("""
        ✅ Karnet sync job completed (asynchronous mode)
        Total pages available: #{total_pages}
        Pages scheduled: #{pages_to_schedule}
        Index page jobs scheduled: #{scheduled_count}
        Events will be processed asynchronously
        """)

        {:ok, %{
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
    else
      # Large sync or chunk - use optimistic page scheduling
      Logger.info("📊 Using optimistic page scheduling for #{limit} events")

      # Estimate pages needed based on events per page
      estimated_pages = calculate_max_pages(limit)
      Logger.info("📋 Scheduling #{estimated_pages} pages optimistically")

      # Schedule IndexPageJobs without checking if pages exist
      # Jobs will handle non-existent pages gracefully
      scheduled_count = schedule_index_page_jobs(estimated_pages, source.id, limit)

      Logger.info("""
      ✅ Karnet sync job completed (optimistic mode)
      Pages scheduled: #{estimated_pages}
      Index page jobs scheduled: #{scheduled_count}
      """)

      {:ok, %{
        pages_scheduled: estimated_pages,
        jobs_scheduled: scheduled_count,
        mode: "optimistic"
      }}
    end
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, _options) do
    Logger.info("""
    🎭 Fetching Karnet events
    City: #{city.name}, #{city.country.name}
    Target events: #{limit}
    """)

    # Verify it's Kraków (Karnet only serves Kraków)
    unless String.downcase(city.name) in ["kraków", "krakow", "cracow"] do
      Logger.warning("⚠️ Karnet scraper is designed for Kraków but got: #{city.name}")
    end

    max_pages = calculate_max_pages(limit)

    # Fetch all index pages
    with {:ok, pages} <- Client.fetch_all_index_pages(max_pages) do
      Logger.info("📚 Fetched #{length(pages)} index pages")

      # Extract basic events from index
      basic_events = IndexExtractor.extract_events_from_pages(pages)
      Logger.info("📋 Extracted #{length(basic_events)} events from index")

      # Apply limit
      limited_events = Enum.take(basic_events, limit)

      # Fetch details for each event
      detailed_events =
        limited_events
        |> Enum.map(&fetch_and_merge_details/1)
        |> Enum.reject(&is_nil/1)

      Logger.info("✅ Successfully fetched #{length(detailed_events)} events with details")
      {:ok, detailed_events}
    else
      {:error, reason} = error ->
        Logger.error("Failed to fetch Karnet events: #{inspect(reason)}")
        error
    end
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Transform each event using our Transformer
    # Filter out events that fail venue validation
    raw_events
    |> Enum.map(&Transformer.transform_event/1)
    |> Enum.filter(fn
      {:ok, _event} -> true
      {:error, _reason} -> false
    end)
    |> Enum.map(fn {:ok, event} -> event end)
  end

  # Required by BaseJob for source configuration
  def source_config do
    %{
      name: "Karnet Kraków",
      slug: "karnet",
      website_url: "https://karnet.krakowculture.pl",
      priority: 70,
      config: %{
        "rate_limit_seconds" => Config.rate_limit(),
        "max_requests_per_hour" => 300,
        "language" => "pl",
        "supports_pagination" => true
      }
    }
  end

  defp determine_page_count(max_pages) do
    Logger.info("🔍 Determining total page count (max: #{max_pages || "unlimited"})")

    # Quick scan to determine how many pages have events
    # We'll fetch pages sequentially until we find one without events
    # This is faster than fetching all pages upfront
    scan_pages_for_count(1, max_pages, 0)
  end

  defp scan_pages_for_count(current_page, max_pages, _last_valid)
       when is_integer(max_pages) and current_page > max_pages do
    {:ok, max_pages}
  end

  defp scan_pages_for_count(current_page, max_pages, last_valid) do
    url = Config.build_events_url(current_page)

    case Client.fetch_page(url) do
      {:ok, html} ->
        if has_events?(html) do
          Logger.debug("✅ Page #{current_page} has events")
          scan_pages_for_count(current_page + 1, max_pages, current_page)
        else
          Logger.info("📭 No events on page #{current_page}, total pages: #{last_valid}")
          {:ok, last_valid}
        end

      {:error, :not_found} ->
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

  defp schedule_index_page_jobs(total_pages, source_id, limit) do
    Logger.info("📅 Scheduling #{total_pages} index page jobs")

    # Schedule IndexPageJobs for each page
    scheduled_jobs =
      1..total_pages
      |> Enum.map(fn page_num ->
        # Stagger the jobs slightly to avoid thundering herd
        # But allow some concurrency (pages can be processed in parallel)
        delay_seconds = div(page_num - 1, 3) * Config.rate_limit()
        scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

        job_args = %{
          "page_number" => page_num,
          "source_id" => source_id,
          "limit" => if(page_num == 1, do: limit, else: nil),
          "total_pages" => total_pages
        }

        EventasaurusDiscovery.Sources.Karnet.Jobs.IndexPageJob.new(
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

  defp has_events?(html) do
    # Check if the HTML contains event listings
    String.contains?(html, "class=\"event-item\"") ||
      String.contains?(html, "class=\"wydarzenie\"") ||
      String.contains?(html, "data-event-id") ||
      (String.contains?(html, "href") && String.contains?(html, "/wydarzenia/"))
  end

  defp get_or_create_karnet_source do
    case Repo.get_by(Source, slug: "karnet") do
      nil ->
        config = source_config()

        %Source{}
        |> Source.changeset(config)
        |> Repo.insert!()

      source ->
        source
    end
  end

  # Private helper functions

  defp fetch_and_merge_details(%{url: url} = basic_event) do
    Logger.debug("🔍 Fetching details for: #{url}")

    case Client.fetch_page(url) do
      {:ok, html} ->
        case DetailExtractor.extract_event_details(html, url) do
          {:ok, details} ->
            # Merge basic and detailed data
            Map.merge(basic_event, details)

          {:error, reason} ->
            Logger.warning("Failed to extract details from #{url}: #{inspect(reason)}")
            nil
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch event page #{url}: #{inspect(reason)}")
        nil
    end
  end

  defp fetch_and_merge_details(basic_event) do
    Logger.warning("Event without URL: #{inspect(basic_event)}")
    nil
  end

  defp calculate_max_pages(limit) do
    # Karnet has ~12 events per page
    events_per_page = 12
    pages = div(limit, events_per_page)
    if rem(limit, events_per_page) > 0, do: pages + 1, else: pages
  end

end
