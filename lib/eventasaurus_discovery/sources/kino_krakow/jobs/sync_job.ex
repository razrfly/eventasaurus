defmodule EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob do
  @moduledoc """
  Coordinator Oban job for syncing Kino Krakow movie showtimes.

  This job orchestrates the movie-based scraping architecture:
  1. Fetches cinema program page to get list of all movies
  2. Schedules one MoviePageJob per movie
  3. Each MoviePageJob:
     - Establishes its own session (no race conditions)
     - Loops through days 0-6 to fetch all showtimes
     - Schedules MovieDetailJob and ShowtimeProcessJobs

  This architecture eliminates race conditions by giving each job
  its own isolated session with independent day-selection state.

  Benefits:
  - No race conditions (each job has isolated session)
  - All data for one movie collected together
  - Natural unit of work (movie = one entity)
  - Parallel processing via Oban queues

  Uses the standardized BaseJob behaviour for consistent processing.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source

  alias EventasaurusDiscovery.Sources.KinoKrakow.{
    Config,
    Extractors.MovieListExtractor,
    Jobs.MoviePageJob
  }

  # Override perform to use movie-based architecture
  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    source_id = args["source_id"] || get_or_create_source_id()
    force = args["force"] || false

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    Logger.info("""
    🎬 Starting Kino Krakow movie-based sync
    Fetching list of movies...
    """)

    # Fetch list of movies from cinema program page
    case fetch_movie_list() do
      {:ok, movies} ->
        # Schedule one MoviePageJob per movie with parent tracking
        scheduled_count = schedule_movie_page_jobs(movies, source_id, force, job_id)

        Logger.info("""
        ✅ Kino Krakow sync job completed (movie-based mode)
        Movies found: #{length(movies)}
        Movie jobs scheduled: #{scheduled_count}
        Each job will fetch all 7 days for its movie
        """)

        {:ok,
         %{
           mode: "movie-based",
           movies_found: length(movies),
           movie_jobs_scheduled: scheduled_count
         }}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch movie list: #{inspect(reason)}")
        {:error, reason}
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

  # Source configuration (required by BaseJob behavior)
  def source_config do
    %{
      name: "Kino Krakow",
      slug: "kino-krakow",
      website_url: Config.base_url(),
      priority: 15,
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

  # Fetch list of movies from cinema program page
  defp fetch_movie_list do
    showtimes_url = Config.showtimes_url()
    headers = [{"User-Agent", Config.user_agent()}]

    Logger.info("📡 Fetching movie list from cinema program")

    case HTTPoison.get(showtimes_url, headers, timeout: Config.timeout()) do
      {:ok, %{status_code: 200, body: html}} ->
        case MovieListExtractor.extract(html) do
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

  # Schedule MoviePageJobs for all movies
  defp schedule_movie_page_jobs(movies, source_id, force, parent_job_id) do
    Logger.info("📽️  Scheduling MoviePageJobs for #{length(movies)} movies")

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

  # Get or create source
  defp get_or_create_source_id do
    case Repo.get_by(Source, slug: "kino-krakow") do
      nil ->
        config = source_config()

        %Source{}
        |> Source.changeset(config)
        |> Repo.insert!()
        |> Map.get(:id)

      source ->
        source.id
    end
  end
end
