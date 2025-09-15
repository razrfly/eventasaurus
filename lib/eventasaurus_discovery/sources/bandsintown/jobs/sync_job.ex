defmodule EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob do
  @moduledoc """
  Unified Oban job for syncing BandsInTown events.

  Processes events inline using the unified discovery pipeline to enable
  collision detection with other sources.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_id = args["city_id"]
    limit = args["limit"] || 100
    max_pages = calculate_max_pages(limit)

    # Get city with coordinates
    city = Repo.get!(City, city_id) |> Repo.preload(:country)

    # Build BandsInTown city slug
    bandsintown_slug = build_bandsintown_slug(city)

    Logger.info("""
    🎵 Starting BandsInTown inline sync
    City: #{city.name}, #{city.country.name}
    Limit: #{limit} events
    Max pages: #{max_pages}
    """)

    # Get or create source
    source = get_or_create_bandsintown_source()

    # Convert coordinates to float
    latitude = Decimal.to_float(city.latitude)
    longitude = Decimal.to_float(city.longitude)

    # Fetch events from API
    # Note: Client.fetch_all_city_events always returns {:ok, events}, even on error (returns empty list)
    {:ok, events} = Client.fetch_all_city_events(latitude, longitude, bandsintown_slug, max_pages: max_pages)

    # Apply limit
    events_to_process = if limit, do: Enum.take(events, limit), else: events

    Logger.info("📋 Found #{length(events_to_process)} BandsInTown events to process")

    # Schedule individual jobs for each event with rate limiting
    enqueued_count = schedule_detail_jobs(events_to_process, source.id)

    Logger.info("""
    ✅ BandsInTown sync job completed
    Events found: #{length(events_to_process)}
    Detail jobs enqueued: #{enqueued_count}
    """)

    {:ok, %{enqueued: enqueued_count, total: length(events_to_process)}}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # This will be implemented when we fully refactor BandsInTown
    {:error, :not_implemented}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # This will be implemented when we fully refactor BandsInTown
    raw_events
  end

  # Required by BaseJob for source configuration
  def source_config do
    %{
      name: "Bandsintown",
      slug: "bandsintown",
      website_url: "https://www.bandsintown.com",
      priority: 80,
      config: %{
        "rate_limit_seconds" => 3,
        "max_requests_per_hour" => 500
      }
    }
  end

  defp schedule_detail_jobs(events, source_id) do
    Logger.info("📅 Scheduling #{length(events)} detail jobs")

    # Schedule individual jobs for each event with rate limiting
    scheduled_jobs = events
    |> Enum.with_index()
    |> Enum.map(fn {event, index} ->
      # Add delay between jobs to respect rate limits
      # Start immediately, then 5 seconds between each job
      scheduled_at = DateTime.add(DateTime.utc_now(), index * 5, :second)

      job_args = %{
        "url" => event.url || event[:url],
        "source_id" => source_id,
        "event_data" => event
      }

      # Create the job changeset
      EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.EventDetailJob.new(job_args,
        queue: "scraper_detail",
        scheduled_at: scheduled_at
      )
      |> Oban.insert()
    end)

    # Count successful insertions
    successful_count = Enum.count(scheduled_jobs, fn
      {:ok, _} -> true
      _ -> false
    end)

    Logger.info("✅ Successfully scheduled #{successful_count}/#{length(events)} detail jobs")
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

  defp build_bandsintown_slug(city) do
    city_slug = city.slug || String.downcase(city.name) |> String.replace(" ", "-")
    country_slug = String.downcase(city.country.name) |> String.replace(" ", "-")
    "#{city_slug}-#{country_slug}"
  end

  defp calculate_max_pages(limit) do
    # Estimate pages based on ~20 events per page
    pages = div(limit, 20)
    if rem(limit, 20) > 0, do: pages + 1, else: pages
  end

end