defmodule EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.CityIndexJob do
  @moduledoc """
  Oban job for fetching events from a Bandsintown city page.

  This job:
  1. Fetches the city page HTML
  2. Extracts event URLs
  3. Schedules EventDetailJob for each event
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Scraping.Helpers.JobMetadata
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    # Accept either city_id or city_slug for backwards compatibility
    city_id = args["city_id"]
    city_slug = args["city_slug"] || args["city"]
    limit = args["limit"]
    use_playwright = Map.get(args, "use_playwright", false)
    max_pages = Map.get(args, "max_pages", 5)  # Default to 5 pages

    # Fetch city from database if city_id provided, otherwise try to find by slug
    city = cond do
      city_id ->
        Repo.get!(City, city_id) |> Repo.preload(:country)
      city_slug ->
        # Try to find city by slug - this is for backwards compatibility
        case Repo.get_by(City, slug: extract_city_name(city_slug)) do
          nil ->
            Logger.error("❌ City not found: #{city_slug}")
            {:error, :city_not_found}
          city ->
            Repo.preload(city, :country)
        end
      true ->
        Logger.error("❌ No city_id or city_slug provided")
        {:error, :no_city_specified}
    end

    # Handle early return if city not found
    case city do
      {:error, reason} ->
        if job_id do
          JobMetadata.update_error(job_id, reason, %{city_id: city_id, city_slug: city_slug})
        end
        {:error, reason}

      city ->
        # Build Bandsintown city slug from city and country
        bandsintown_slug = build_bandsintown_slug(city)

        Logger.info("""
        🏙️ Starting Bandsintown City Index Job
        City: #{city.name}, #{city.country.name}
        Coordinates: (#{city.latitude}, #{city.longitude})
        Bandsintown slug: #{bandsintown_slug}
        Limit: #{limit || "none"}
        Max pages: #{max_pages}
        Playwright: #{use_playwright}
        """)

        # Get or create source
        source = get_or_create_source()

        # Convert Decimal coordinates to float
        latitude = Decimal.to_float(city.latitude)
        longitude = Decimal.to_float(city.longitude)

        try do
          # Use the new pagination API with coordinates
          fetch_result = Client.fetch_all_city_events(
            latitude,
            longitude,
            bandsintown_slug,
            max_pages: max_pages
          )

          case fetch_result do
            {:ok, events} ->
              process_events(events, source, job_id, limit)
          end
        rescue
          e ->
            Logger.error("❌ City Index Job failed: #{Exception.message(e)}")
            if job_id do
              JobMetadata.update_error(job_id, e, %{
                city_id: city.id,
                city_name: city.name,
                coordinates: {latitude, longitude}
              })
            end
            {:error, e}
        end
    end
  end

  defp process_events(events, source, job_id, limit) do
    total_events = length(events)

    # Apply limit if specified
    events_to_process = if limit do
      Logger.info("🧪 Limiting to #{limit} events (found #{total_events})")
      Enum.take(events, limit)
    else
      events
    end

    processed_count = length(events_to_process)

    # Log extracted events for debugging
    Logger.info("📋 Events to process:")
    Enum.each(events_to_process, fn event ->
      Logger.info("  - #{event.artist_name || event[:artist_name]} at #{event.venue_name || event[:venue_name]} on #{event.date || event[:date]}")
      Logger.info("    URL: #{event.url || event[:url]}")
    end)

    # Schedule detail jobs with rate limiting
    enqueued_count = schedule_detail_jobs(events_to_process, source.id)

    # Update job metadata
    metadata = %{
      total_events: total_events,
      processed_count: processed_count,
      enqueued_count: enqueued_count,
      source_id: source.id,
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    if job_id do
      JobMetadata.update_index_job(job_id, metadata)
    end

    Logger.info("""
    ✅ City Index Job completed
    Total events found: #{total_events}
    Events processed: #{processed_count}
    Detail jobs enqueued: #{enqueued_count}
    """)

    {:ok, metadata}
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

  defp get_or_create_source do
    case Repo.get_by(Source, slug: "bandsintown") do
      nil ->
        %Source{}
        |> Source.changeset(%{
          name: "Bandsintown",
          slug: "bandsintown",
          website_url: "https://www.bandsintown.com",
          priority: 80,
          config: %{
            "rate_limit_seconds" => 3,
            "max_requests_per_hour" => 500
          }
        })
        |> Repo.insert!()

      source ->
        source
    end
  end

  # Helper to extract city name from old-style slugs like "krakow-poland"
  defp extract_city_name(city_slug) when is_binary(city_slug) do
    parts = city_slug |> String.downcase() |> String.split("-")
    parts |> Enum.drop(-1) |> Enum.join("-")
  end
  defp extract_city_name(_), do: nil

  # Build the Bandsintown URL slug from city and country
  defp build_bandsintown_slug(city) do
    city_slug = city.slug || String.downcase(city.name) |> String.replace(" ", "-")
    country_slug = String.downcase(city.country.name) |> String.replace(" ", "-")
    "#{city_slug}-#{country_slug}"
  end
end