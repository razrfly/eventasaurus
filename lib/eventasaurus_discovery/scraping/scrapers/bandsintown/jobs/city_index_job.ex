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
  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Scraping.RateLimiter
  alias EventasaurusDiscovery.Scraping.Helpers.JobMetadata
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.{Client, Extractor}
  # alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.EventDetailJob

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
        JobMetadata.update_error(job_id, reason, context: %{city_id: city_id, city_slug: city_slug})
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

            {:error, :playwright_not_configured} ->
              # Fallback to pagination API
              Logger.warning("⚠️ Playwright not configured, using pagination API...")

              case Client.fetch_all_city_events(latitude, longitude, bandsintown_slug, max_pages: max_pages) do
                {:ok, events} ->
                  process_events(events, source, job_id, limit)

                {:error, reason} = error ->
                  JobMetadata.update_error(job_id, reason, context: %{
                    city_id: city.id,
                    city_name: city.name,
                    coordinates: {latitude, longitude}
                  })
                  error
              end

            {:error, reason} = error ->
              JobMetadata.update_error(job_id, reason, context: %{
                city_id: city.id,
                city_name: city.name,
                coordinates: {latitude, longitude}
              })
              error
          end
        rescue
          e ->
            Logger.error("❌ City Index Job failed: #{Exception.message(e)}")
            JobMetadata.update_error(job_id, e, context: %{
              city_id: city.id,
              city_name: city.name,
              coordinates: {latitude, longitude}
            })
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

    JobMetadata.update_index_job(job_id, metadata)

    Logger.info("""
    ✅ City Index Job completed
    Total events found: #{total_events}
    Events processed: #{processed_count}
    Detail jobs enqueued: #{enqueued_count}
    """)

    {:ok, metadata}
  end

  defp schedule_detail_jobs(events, _source_id) do
    # For now, we'll just count them since EventDetailJob isn't implemented yet
    Logger.info("📅 Would schedule #{length(events)} detail jobs")

    # TODO: Uncomment when EventDetailJob is implemented
    # RateLimiter.schedule_detail_jobs(
    #   events,
    #   EventDetailJob,
    #   fn event ->
    #     %{
    #       "url" => event.url,
    #       "source_id" => source_id,
    #       "event_data" => event
    #     }
    #   end
    # )

    length(events)
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
    city_slug
    |> String.split("-")
    |> List.first()
    |> String.downcase()
  end
  defp extract_city_name(_), do: nil

  # Build the Bandsintown URL slug from city and country
  defp build_bandsintown_slug(city) do
    city_slug = city.slug || String.downcase(city.name) |> String.replace(" ", "-")
    country_slug = String.downcase(city.country.name) |> String.replace(" ", "-")
    "#{city_slug}-#{country_slug}"
  end
end