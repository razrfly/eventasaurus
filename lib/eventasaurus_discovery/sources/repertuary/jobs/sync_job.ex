defmodule EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob do
  @moduledoc """
  Coordinator Oban job for syncing Repertuary.pl movie showtimes.

  This job orchestrates the movie-based scraping architecture for any city
  in the repertuary.pl network (Krakow, Warsaw, Gdansk, etc.):

  1. Fetches cinema program page to get list of all movies
  2. Schedules one MoviePageJob per movie
  3. Each MoviePageJob:
     - Establishes its own session (no race conditions)
     - Loops through days 0-6 to fetch all showtimes
     - Schedules MovieDetailJob and ShowtimeProcessJobs

  ## Multi-City Support

  Pass `"city"` in job args to scrape a specific city:

      SyncJob.new(%{"city" => "warszawa"}) |> Oban.insert()

  Defaults to "krakow" for backward compatibility.

  ## Benefits

  - No race conditions (each job has isolated session)
  - All data for one movie collected together
  - Natural unit of work (movie = one entity)
  - Parallel processing via Oban queues
  - Single codebase supports 29+ Polish cities

  Uses the standardized BaseJob behaviour for consistent processing.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.SourceStore

  alias EventasaurusDiscovery.Sources.Repertuary.{
    Config,
    Cities,
    Extractors.MovieListExtractor,
    Jobs.MoviePageJob
  }

  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # Override perform to use movie-based architecture
  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args} = job) do
    # Get city from args, checking both options (from DiscoverySyncJob) and top-level (direct calls)
    # This supports both the admin dashboard flow and direct job creation
    options = args["options"] || %{}

    city =
      options["city"] || options[:city] || args["city"] || Config.default_city()

    case Cities.get(city) do
      nil ->
        Logger.error("❌ Unknown city: #{city}")
        {:error, :unknown_city}

      city_config ->
        do_perform(job, job_id, args, city, city_config)
    end
  end

  defp do_perform(job, job_id, args, city, city_config) do
    source_id = args["source_id"] || get_or_create_source_id()
    force = args["force"] || false

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    Logger.info("""
    🎬 Starting Repertuary.pl movie-based sync
    City: #{city_config.name}
    Base URL: #{city_config.base_url}
    Fetching list of movies...
    """)

    # External ID for tracking - includes city for uniqueness
    external_id = "repertuary_#{city}_sync_#{Date.utc_today()}"

    # Fetch list of movies from cinema program page
    result =
      case fetch_movie_list(city) do
        {:ok, movies} ->
          # Schedule one MoviePageJob per movie with parent tracking
          scheduled_count = schedule_movie_page_jobs(movies, source_id, city, force, job_id)

          Logger.info("""
          ✅ Repertuary.pl sync job completed (movie-based mode)
          City: #{city_config.name}
          Movies found: #{length(movies)}
          Movie jobs scheduled: #{scheduled_count}
          Each job will fetch all 7 days for its movie
          """)

          {:ok,
           %{
             mode: "movie-based",
             city: city,
             city_name: city_config.name,
             movies_found: length(movies),
             movie_jobs_scheduled: scheduled_count
           }}

        {:error, reason} ->
          Logger.error("❌ Failed to fetch movie list for #{city_config.name}: #{inspect(reason)}")
          {:error, reason}
      end

    # Track metrics
    case result do
      {:ok, _stats} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result
    end
  end

  # Implement required BaseJob callbacks (for backward compatibility)

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # This method is not used in distributed mode
    # Kept for BaseJob behaviour compliance
    {:error, :use_distributed_mode}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(_raw_events) do
    # This method is not used in distributed mode
    # Transformation happens in ShowtimeProcessJob
    []
  end

  @doc """
  Get unified source configuration for Repertuary.
  All cities share a single source record (Cinema City pattern).
  """
  def source_config do
    %{
      name: "Repertuary",
      slug: "repertuary",
      website_url: "https://repertuary.pl",
      priority: 15,
      domains: ["movies", "cinema"],
      is_active: true,
      aggregate_on_index: true,
      aggregation_type: "ScreeningEvent",
      config: %{
        "rate_limit_seconds" => Config.rate_limit(),
        "max_requests_per_hour" => 1800,
        "language" => "pl",
        "supports_tmdb_matching" => true,
        "supports_movie_metadata" => true
      }
    }
  end

  # Private functions

  # Fetch list of movies from cinema program page for a specific city
  defp fetch_movie_list(city) do
    showtimes_url = Config.showtimes_url(city)
    headers = [{"User-Agent", Config.user_agent()}]

    Logger.info("📡 Fetching movie list from #{showtimes_url}")

    case HTTPoison.get(showtimes_url, headers, timeout: Config.timeout()) do
      {:ok, %{status_code: 200, body: html}} ->
        case MovieListExtractor.extract(ensure_utf8(html)) do
          {:ok, movies} ->
            Logger.info("✅ Found #{length(movies)} movies")
            {:ok, movies}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status} fetching movie list"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Schedule MoviePageJobs for all movies, passing city through the chain
  defp schedule_movie_page_jobs(movies, source_id, city, force, parent_job_id) do
    city_config = Cities.get(city)
    Logger.info("📽️  Scheduling MoviePageJobs for #{length(movies)} movies in #{city_config.name}")

    scheduled_jobs =
      movies
      |> Enum.with_index()
      |> Enum.map(fn {movie, index} ->
        # Stagger jobs to avoid thundering herd and respect rate limits
        # Each job will take ~15 seconds (7 days × 2 requests/day)
        delay_seconds = index * Config.rate_limit()

        MoviePageJob.new(
          %{
            "movie_slug" => movie.movie_slug,
            "movie_title" => movie.movie_title,
            "source_id" => source_id,
            "city" => city,
            "force" => force
          },
          queue: :scraper_detail,
          schedule_in: delay_seconds,
          meta: %{"parent_job_id" => parent_job_id}
        )
        |> Oban.insert()
      end)

    # Count successful insertions
    Enum.count(scheduled_jobs, fn
      {:ok, _} -> true
      _ -> false
    end)
  end

  # Get or create the unified Repertuary source using SourceStore
  # All cities share a single source record - city is passed via job args
  defp get_or_create_source_id do
    {:ok, source} = SourceStore.get_or_create_source(source_config())
    source.id
  end

  defp ensure_utf8(body) when is_binary(body) do
    EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8_with_logging(body, "Repertuary SyncJob HTTP response")
  end

  defp ensure_utf8(body), do: body
end
