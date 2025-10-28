defmodule EventasaurusDiscovery.Sources.Waw4Free.Jobs.SyncJob do
  @moduledoc """
  Unified Oban job for syncing Waw4Free Warsaw free events.

  Phase 1 PLACEHOLDER: Basic structure only.
  Phase 3 TODO: Implement category listing scraping logic.

  This job will:
  1. Scrape all 8 category listing pages (no pagination needed)
  2. Extract event URLs from listings
  3. Check EventFreshnessChecker to filter recently-seen events
  4. Enqueue EventDetailJob for events needing updates
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.Source

  alias EventasaurusDiscovery.Sources.Waw4Free.{
    Config,
    Client,
    IndexExtractor
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Sources.Waw4Free.Jobs.EventDetailJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_id = args["city_id"]
    limit = args["limit"] || 200

    # Get city (should be Warsaw/Warszawa)
    city =
      if city_id do
        Repo.get(City, city_id)
      else
        # If no city_id provided, look up Warsaw by name
        import Ecto.Query

        Repo.one(
          from(c in City, where: c.name in ["Warszawa", "Warsaw", "Warschau"], limit: 1)
        )
      end

    case city do
      nil ->
        Logger.error("City not found: #{inspect(city_id)} (tried lookup by name: Warszawa)")
        {:error, :city_not_found}

      city ->
        city = Repo.preload(city, :country)

        # Verify it's Warsaw
        unless String.downcase(city.name) in ["warszawa", "warsaw", "warschau"] do
          Logger.warning("⚠️ Waw4Free scraper is designed for Warsaw but got: #{city.name}")
        end

        Logger.info("""
        🎉 Starting Waw4Free Warsaw sync
        City: #{city.name}, #{city.country.name}
        Limit: #{limit} events
        Categories: #{length(Config.categories())}
        """)

        source = get_or_create_waw4free_source()

        # Scrape all category pages and enqueue EventDetailJobs
        result = scrape_categories(source, limit)

        case result do
          {:ok, stats} ->
            Logger.info("""
            ✅ Waw4Free sync job completed
            Categories scraped: #{stats.categories_scraped}
            Events discovered: #{stats.events_discovered}
            Fresh events: #{stats.fresh_events}
            Jobs enqueued: #{stats.jobs_enqueued}
            """)

            # Schedule coordinate recalculation after successful sync
            schedule_coordinate_update(city_id)
            Logger.info("🗺️ Scheduled coordinate update for city #{city_id}")

            {:ok, stats}
        end
    end
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # Not used - we use two-stage scraping (SyncJob + EventDetailJob)
    Logger.warning("⚠️ fetch_events not used for Waw4Free (uses two-stage scraping)")
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(_raw_events) do
    # Not used - transformation happens in EventDetailJob
    Logger.warning("⚠️ transform_events not used for Waw4Free (handled in EventDetailJob)")
    []
  end

  # Private helper functions

  defp scrape_categories(source, limit) do
    categories = Config.categories()
    Logger.info("📚 Scraping #{length(categories)} category pages")

    # Scrape each category page
    {events_by_category, errors} =
      categories
      |> Enum.map(&scrape_category(&1, source))
      |> Enum.split_with(fn
        {:ok, _events} -> true
        {:error, _reason} -> false
      end)

    # Extract events from successful results
    all_events =
      events_by_category
      |> Enum.flat_map(fn {:ok, events} -> events end)
      |> Enum.reject(&is_nil(&1.external_id))
      |> Enum.uniq_by(& &1.external_id)

    # Log errors
    if length(errors) > 0 do
      Logger.warning("⚠️ Failed to scrape #{length(errors)} categories")
      Enum.each(errors, fn {:error, {category, reason}} ->
        Logger.error("Category '#{category}' failed: #{inspect(reason)}")
      end)
    end

    Logger.info("📊 Discovered #{length(all_events)} unique events across all categories")

    # Check freshness and filter events
    fresh_events = filter_fresh_events(all_events, source.id)

    Logger.info("✨ #{length(fresh_events)} fresh events need processing")

    # Apply limit
    limited_events = Enum.take(fresh_events, limit)

    # Enqueue EventDetailJob for each fresh event
    jobs_enqueued = enqueue_event_detail_jobs(limited_events, source.id)

    {:ok,
     %{
       categories_scraped: length(categories) - length(errors),
       events_discovered: length(all_events),
       fresh_events: length(fresh_events),
       jobs_enqueued: jobs_enqueued,
       errors: length(errors)
     }}
  end

  defp scrape_category(category, _source) do
    url = Config.build_category_url(category)
    Logger.debug("🔍 Scraping category: #{category} (#{url})")

    case Client.fetch_page(url) do
      {:ok, html} ->
        events = IndexExtractor.extract_events_from_html(html)
        Logger.info("📋 Found #{length(events)} events in '#{category}' category")
        {:ok, events}

      {:error, reason} ->
        Logger.error("Failed to fetch category '#{category}': #{inspect(reason)}")
        {:error, {category, reason}}
    end
  end

  defp filter_fresh_events(events, source_id) do
    # Use EventFreshnessChecker to filter out recently-seen events
    # EventFreshnessChecker expects maps with string keys
    events_as_maps = Enum.map(events, fn event ->
      %{
        "external_id" => event.external_id,
        "url" => event.url,
        "title" => event.title,
        "extracted_at" => event.extracted_at
      }
    end)

    fresh_maps = EventFreshnessChecker.filter_events_needing_processing(events_as_maps, source_id)
    fresh_external_ids = MapSet.new(fresh_maps, & &1["external_id"])

    # Filter original events to only those in fresh set
    Enum.filter(events, fn event ->
      MapSet.member?(fresh_external_ids, event.external_id)
    end)
  end

  defp enqueue_event_detail_jobs(events, source_id) do
    Logger.info("📬 Enqueueing #{length(events)} EventDetailJobs")

    scheduled_jobs =
      events
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        # Stagger each job by rate_limit seconds (+ jitter) to avoid bursty first requests
        delay_seconds = index * Config.rate_limit() + :rand.uniform(1) - 1
        scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

        job_args = %{
          "url" => event.url,
          "source_id" => source_id,
          "external_id" => event.external_id,
          "event_metadata" => %{
            "title" => event.title,
            "extracted_at" => DateTime.to_iso8601(event.extracted_at)
          }
        }

        EventDetailJob.new(job_args, scheduled_at: scheduled_at)
        |> Oban.insert()
      end)

    # Count successful insertions
    successful_count =
      Enum.count(scheduled_jobs, fn
        {:ok, _} -> true
        _ -> false
      end)

    Logger.info("✅ Successfully enqueued #{successful_count}/#{length(events)} EventDetailJobs")
    successful_count
  end

  def source_config do
    %{
      name: "Waw4Free",
      slug: "waw4free",
      website_url: "https://waw4free.pl",
      priority: 35,
      config: %{
        "rate_limit_seconds" => Config.rate_limit(),
        "max_requests_per_hour" => 300,
        "language" => "pl",
        "supports_pagination" => false,
        "all_events_free" => true
      }
    }
  end

  defp get_or_create_waw4free_source do
    case Repo.get_by(Source, slug: "waw4free") do
      nil ->
        config = source_config()

        %Source{}
        |> Source.changeset(config)
        |> Repo.insert!()

      source ->
        source
    end
  end
end
