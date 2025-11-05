defmodule EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob do
  @moduledoc """
  Coordinator Oban job for syncing Kino Krakow movie showtimes.

  This job orchestrates the distributed scraping architecture:
  1. Establishes session cookies via initial HTTP request
  2. Schedules 7 DayPageJobs (one per day 0-6)
  3. Each DayPageJob schedules MovieDetailJobs for unique movies
  4. Each MovieDetailJob schedules ShowtimeProcessJobs for showtimes

  This distributed approach provides:
  - Granular visibility into TMDB matching failures
  - Individual retry logic per movie
  - Parallel processing via Oban queues
  - Better failure isolation

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
    Jobs.DayPageJob
  }

  # Override perform to use distributed architecture
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    source_id = args["source_id"] || get_or_create_source_id()
    force = args["force"] || false

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    Logger.info("""
    🎬 Starting Kino Krakow distributed sync
    Scheduling DayPageJob for current day (day 0)
    """)

    # Initial request to get session cookies
    case establish_session() do
      {:ok, cookies} ->
        # Schedule DayPageJobs for days 0-6
        scheduled_count = schedule_day_jobs(cookies, source_id, force)

        Logger.info("""
        ✅ Kino Krakow sync job completed (distributed mode)
        Day jobs scheduled: #{scheduled_count}
        Events will be processed asynchronously
        """)

        {:ok,
         %{
           mode: "distributed",
           day_jobs_scheduled: scheduled_count
         }}

      {:error, reason} ->
        Logger.error("❌ Failed to establish session: #{inspect(reason)}")
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

  # Establish session by fetching initial page to get cookies
  defp establish_session do
    showtimes_url = Config.showtimes_url()
    headers = [{"User-Agent", Config.user_agent()}]

    Logger.info("📡 Establishing session with Kino Krakow")

    case HTTPoison.get(showtimes_url, headers, timeout: Config.timeout()) do
      {:ok, %{status_code: 200, headers: response_headers}} ->
        cookies = extract_cookies(response_headers)
        Logger.info("✅ Session established")
        {:ok, cookies}

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status} on initial request"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract cookies from response headers
  defp extract_cookies(headers) do
    headers
    |> Enum.filter(fn {name, _} -> String.downcase(name) == "set-cookie" end)
    |> Enum.map(fn {_, value} ->
      # Extract cookie name=value, ignore attributes after semicolon
      value |> String.split(";") |> hd()
    end)
    |> Enum.join("; ")
  end

  # Schedule DayPageJobs for days 0-6
  defp schedule_day_jobs(cookies, source_id, force) do
    # TEMPORARY: Only schedule day 0 (current day) until multi-day is implemented
    # Future: Change [0] to 0..6 when ready for multi-day support
    # Only current day for now
    scheduled_jobs =
      [0]
      |> Enum.map(fn day_offset ->
        # Stagger jobs slightly to avoid thundering herd
        delay_seconds = day_offset * Config.rate_limit()

        DayPageJob.new(
          %{
            "day_offset" => day_offset,
            "cookies" => cookies,
            "source_id" => source_id,
            "force" => force
          },
          queue: :scraper_index,
          schedule_in: delay_seconds
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
