defmodule EventasaurusDiscovery.Sources.Repertuary.Jobs.DayPageJob do
  @moduledoc """
  Oban job for processing a single day's showtimes from Repertuary.pl.

  This job is part of a distributed scraping strategy that prevents timeouts
  by breaking up the multi-day scraping into smaller, concurrent units of work.

  Each DayPageJob:
  1. Sets the active day via POST to /settings/set_day/{day_offset}
  2. Fetches showtimes for that specific day
  3. Extracts showtimes from HTML
  4. Identifies unique movies from the day's showtimes
  5. Schedules MovieDetailJobs for each unique movie
  6. Caches showtimes for later ShowtimeProcessJob processing

  This allows for:
  - Better failure isolation (one day failing doesn't affect others)
  - Concurrent processing of multiple days
  - More granular progress tracking
  - Ability to resume from partial failures
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.Repertuary.{
    Config,
    Extractors.ShowtimeExtractor
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    day_offset = args["day_offset"]
    cookies = args["cookies"]
    csrf_token = args["csrf_token"]
    source_id = args["source_id"]
    force = args["force"] || false

    Logger.info("""
    📅 Processing Repertuary day #{day_offset}
    Source ID: #{source_id}
    CSRF Token: #{String.slice(csrf_token || "none", 0..9)}...
    """)

    # External ID for tracking
    external_id = "repertuary_day_#{day_offset}_#{Date.utc_today()}"

    # Set the day and fetch showtimes
    result =
      with {:ok, html} <- fetch_day_showtimes(day_offset, cookies, csrf_token),
           showtimes <- extract_showtimes(html, day_offset) do
        # Find unique movies from this day's showtimes
        unique_movies =
          showtimes
          |> Enum.map(& &1.movie_slug)
          |> Enum.uniq()

        Logger.info("""
        ✅ Day #{day_offset} processed
        Showtimes: #{length(showtimes)}
        Unique movies: #{length(unique_movies)}
        """)

        # Schedule MovieDetailJobs for unique movies (with deduplication)
        movies_scheduled = schedule_movie_detail_jobs(unique_movies, source_id)

        # Schedule ShowtimeProcessJobs for each showtime
        # These will wait for MovieDetailJobs to complete via caching mechanism
        # Pass unique_movies count to calculate appropriate delay
        showtimes_scheduled =
          schedule_showtime_jobs(showtimes, source_id, day_offset, length(unique_movies), force)

        {:ok,
         %{
           day: day_offset,
           showtimes_count: length(showtimes),
           unique_movies: length(unique_movies),
           movies_scheduled: movies_scheduled,
           showtimes_scheduled: showtimes_scheduled
         }}
      else
        {:error, reason} ->
          Logger.error("❌ Failed to process day #{day_offset}: #{inspect(reason)}")
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

  # Fetch showtimes for a specific day
  defp fetch_day_showtimes(day_offset, cookies, csrf_token) do
    base_url = Config.base_url()
    showtimes_url = Config.showtimes_url()

    # Headers for POST request with Rails UJS and CSRF token
    post_headers = [
      {"User-Agent", Config.user_agent()},
      {"Accept", "*/*"},
      {"X-Requested-With", "XMLHttpRequest"},
      {"Referer", showtimes_url},
      {"X-CSRF-Token", csrf_token},
      {"Cookie", cookies}
    ]

    # Headers for GET request
    get_headers = [
      {"User-Agent", Config.user_agent()},
      {"Cookie", cookies}
    ]

    # 1. Set the day via POST
    set_day_url = "#{base_url}/settings/set_day/#{day_offset}"
    rate_limit_delay()

    case HTTPoison.post(set_day_url, "", post_headers, timeout: Config.timeout()) do
      {:ok, %{status_code: status}} when status in [200, 302] ->
        # 2. Fetch showtimes for this day
        rate_limit_delay()

        case HTTPoison.get(showtimes_url, get_headers, timeout: Config.timeout()) do
          {:ok, %{status_code: 200, body: html}} ->
            {:ok, ensure_utf8(html)}

          {:ok, %{status_code: status}} ->
            {:error, "HTTP #{status} fetching showtimes"}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status} setting day"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract showtimes from HTML
  defp extract_showtimes(html, day_offset) do
    # Calculate the actual date for this day offset
    date = Date.add(Date.utc_today(), day_offset)

    showtimes = ShowtimeExtractor.extract(html, date)
    Logger.debug("📋 Extracted #{length(showtimes)} showtimes for day #{day_offset} (#{date})")

    showtimes
  end

  # Schedule MovieDetailJobs for unique movies
  defp schedule_movie_detail_jobs(movie_slugs, source_id) do
    Logger.info("📽️ Scheduling #{length(movie_slugs)} MovieDetailJobs")

    scheduled_jobs =
      movie_slugs
      |> Enum.with_index()
      |> Enum.map(fn {movie_slug, index} ->
        # Stagger job execution with rate limiting
        delay_seconds = index * Config.rate_limit()

        EventasaurusDiscovery.Sources.Repertuary.Jobs.MovieDetailJob.new(
          %{
            "movie_slug" => movie_slug,
            "source_id" => source_id
          },
          queue: :scraper_detail,
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

  # Schedule ShowtimeProcessJobs for each showtime
  defp schedule_showtime_jobs(showtimes, source_id, day_offset, movie_count, force) do
    # Calculate delay to give MovieDetailJobs time to complete first
    # Each MovieDetailJob is scheduled with delays based on its index: index * Config.rate_limit()
    # Last movie starts at: (movie_count - 1) * rate_limit
    # Add buffer for movie processing time (fetch + TMDB matching): ~30 seconds
    rate_limit = Config.rate_limit()
    # Ensure all movies are cached before showtimes process
    base_delay = movie_count * rate_limit + 30

    # Add external_ids to showtimes for freshness checking
    # Must match the external_id generation in ShowtimeProcessJob
    showtimes_with_ids =
      Enum.map(showtimes, fn showtime ->
        showtime_map = if is_struct(showtime), do: Map.from_struct(showtime), else: showtime

        # Extract fields for external_id (matching ShowtimeProcessJob logic)
        movie = showtime_map[:movie_slug] || showtime_map["movie_slug"]
        cinema = showtime_map[:cinema_slug] || showtime_map["cinema_slug"]
        datetime = showtime_map[:datetime] || showtime_map["datetime"]

        # Extract date and time components
        date = DateTime.to_date(datetime) |> Date.to_iso8601()
        time = DateTime.to_time(datetime) |> Time.to_string() |> String.slice(0..4)

        # Generate external_id matching ShowtimeProcessJob pattern
        external_id =
          "repertuary_showtime_#{movie}_#{cinema}_#{date}_#{time}"
          |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")

        Map.put(showtime_map, :external_id, external_id)
      end)

    # Filter out fresh showtimes (seen within threshold) unless force=true
    showtimes_to_process =
      if force do
        showtimes_with_ids
      else
        EventFreshnessChecker.filter_events_needing_processing(
          showtimes_with_ids,
          source_id
        )
      end

    # Log efficiency metrics
    total_showtimes = length(showtimes)
    skipped = total_showtimes - length(showtimes_to_process)
    threshold = EventFreshnessChecker.get_threshold()

    Logger.info("""
    🔄 Repertuary Freshness Check: Day #{day_offset}
    Processing #{length(showtimes_to_process)}/#{total_showtimes} showtimes #{if force, do: "(Force mode)", else: "(#{skipped} fresh, threshold: #{threshold}h)"}
    """)

    scheduled_jobs =
      showtimes_to_process
      |> Enum.with_index()
      |> Enum.map(fn {showtime, index} ->
        # Stagger job execution
        # 2 seconds between showtimes
        delay_seconds = base_delay + index * 2

        EventasaurusDiscovery.Sources.Repertuary.Jobs.ShowtimeProcessJob.new(
          %{
            "showtime" => showtime,
            "source_id" => source_id
          },
          queue: :scraper,
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

  # Rate limiting
  defp rate_limit_delay do
    Process.sleep(Config.rate_limit() * 1000)
  end

  defp ensure_utf8(body) when is_binary(body) do
    EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8_with_logging(body, "Repertuary DayPageJob HTTP response")
  end

  defp ensure_utf8(body), do: body
end
