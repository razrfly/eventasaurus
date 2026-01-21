defmodule EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob do
  @moduledoc """
  Coordinator Oban job for syncing Cinema City movie showtimes.

  This job orchestrates the distributed scraping architecture:
  1. Fetches cinema list from Cinema City API
  2. Filters to target cities (Kraków initially)
  3. Schedules CinemaDateJobs for each cinema × date combination
  4. Each CinemaDateJob schedules MovieDetailJobs for unique movies
  5. Each MovieDetailJob schedules ShowtimeProcessJobs for showtimes

  This distributed approach provides:
  - Granular visibility into TMDB matching failures
  - Individual retry logic per movie
  - Parallel processing via Oban queues
  - Better failure isolation
  - Multi-day showtime coverage

  Uses the standardized BaseJob behaviour for consistent processing.
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

  alias EventasaurusDiscovery.Sources.CinemaCity.{
    Client,
    Config,
    Extractors.CinemaExtractor,
    Jobs.CinemaDateJob
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    source_id = args["source_id"] || get_or_create_source_id()
    options = args["options"] || %{}

    # Get city_name from options (set in admin UI per-city discovery config)
    # Falls back to legacy target_cities for backward compatibility
    city_name = options["city_name"] || options[:city_name]

    days_ahead =
      options["days_ahead"] || options[:days_ahead] || args["days_ahead"] || Config.days_ahead()

    force = args["force"] || false
    external_id = "cinema_city_sync_#{Date.utc_today()}"

    # Validate city_name is configured (reject nil and empty string)
    if is_nil(city_name) or city_name == "" do
      error_msg =
        "No city_name configured for cinema-city source. Configure via Admin > Discovery > City Config."

      Logger.error("❌ #{error_msg}")
      # Use standard category for ErrorCategories.categorize_error/1
      # See docs/error-handling-guide.md for category definitions
      MetricsTracker.record_failure(job, :validation_error, external_id)
      {:error, :city_name_not_configured}
    else
      perform_sync(job, source_id, city_name, days_ahead, force, external_id)
    end
  end

  defp perform_sync(job, source_id, city_name, days_ahead, force, external_id) do
    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    Logger.info("""
    🎬 Starting Cinema City distributed sync
    Days ahead: #{days_ahead}
    Target city: #{city_name}
    """)

    # Fetch cinema list from API
    until_date = Date.utc_today() |> Date.add(days_ahead) |> Date.to_iso8601()

    case Client.fetch_cinema_list(until_date) do
      {:ok, cinemas} ->
        # Filter to configured city (single city per discovery config)
        filtered_cinemas = CinemaExtractor.filter_by_city(cinemas, city_name)

        Logger.info("""
        ✅ Found #{length(cinemas)} total cinemas
        📍 Filtered to #{length(filtered_cinemas)} cinema(s) in #{city_name}
        """)

        if Enum.empty?(filtered_cinemas) do
          Logger.warning("⚠️ No cinemas found in #{city_name}")
          MetricsTracker.record_success(job, external_id)
          {:ok, %{cinemas: 0, jobs_scheduled: 0}}
        else
          # Schedule CinemaDateJobs for each cinema × date
          jobs_scheduled =
            schedule_cinema_date_jobs(filtered_cinemas, source_id, days_ahead, force)

          Logger.info("""
          ✅ Cinema City sync job completed (distributed mode)
          City: #{city_name}
          Cinemas: #{length(filtered_cinemas)}
          Days: #{days_ahead}
          CinemaDateJobs scheduled: #{jobs_scheduled}
          Events will be processed asynchronously
          """)

          MetricsTracker.record_success(job, external_id)

          {:ok,
           %{
             mode: "distributed",
             city: city_name,
             cinemas: length(filtered_cinemas),
             days_ahead: days_ahead,
             jobs_scheduled: jobs_scheduled
           }}
        end

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch cinema list: #{inspect(reason)}")

        # Use standard category for ErrorCategories.categorize_error/1
        # See docs/error-handling-guide.md for category definitions
        MetricsTracker.record_failure(job, :network_error, external_id)

        error
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
      name: "Cinema City",
      slug: "cinema-city",
      website_url: Config.base_url(),
      priority: 15,
      domains: ["movies", "cinema"],
      aggregate_on_index: true,
      aggregation_type: "ScreeningEvent",
      config: %{
        "rate_limit_seconds" => Config.rate_limit(),
        "max_requests_per_hour" => 1800,
        "language" => "pl",
        "supports_tmdb_matching" => true,
        "supports_movie_metadata" => true,
        "supports_api" => true
      }
    }
  end

  # Private functions

  # Schedule CinemaDateJobs for each cinema × date combination
  defp schedule_cinema_date_jobs(cinemas, source_id, days_ahead, force) do
    # Generate date range: today through days_ahead
    dates =
      0..(days_ahead - 1)
      |> Enum.map(fn offset -> Date.add(Date.utc_today(), offset) end)

    # Create jobs for each cinema × date combination
    scheduled_jobs =
      for cinema <- cinemas,
          date <- dates do
        cinema_data = CinemaExtractor.extract(cinema)

        # Stagger jobs to respect rate limiting
        # Each cinema gets staggered within its date group
        cinema_index = Enum.find_index(cinemas, &(&1 == cinema)) || 0
        date_offset = Date.diff(date, Date.utc_today())
        # Total delay: (date_offset * cinemas * rate_limit) + (cinema_index * rate_limit)
        delay_seconds =
          date_offset * length(cinemas) * Config.rate_limit() + cinema_index * Config.rate_limit()

        CinemaDateJob.new(
          %{
            "cinema_data" => cinema_data,
            "cinema_city_id" => cinema_data.cinema_city_id,
            "date" => Date.to_iso8601(date),
            "source_id" => source_id,
            "force" => force
          },
          queue: :scraper_index,
          schedule_in: delay_seconds
        )
        |> Oban.insert()
      end

    # Count successful insertions
    Enum.count(scheduled_jobs, fn
      {:ok, _} -> true
      _ -> false
    end)
  end

  # Get or create source
  defp get_or_create_source_id do
    case JobRepo.get_by(Source, slug: "cinema-city") do
      nil ->
        config = source_config()

        %Source{}
        |> Source.changeset(config)
        |> JobRepo.insert!()
        |> Map.get(:id)

      source ->
        source.id
    end
  end
end
