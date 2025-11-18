defmodule EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob do
  @moduledoc """
  Oban job for processing a single movie's showtimes across all 7 days.

  This job establishes its own session and loops through days 0-6,
  fetching the movie's page for each day to collect all showtimes.

  This architecture eliminates the race condition from the old DayPageJob
  approach by ensuring each job has an isolated session with its own
  day-selection state.

  Each MoviePageJob:
  1. Establishes fresh session (GET movie page → receive cookies + CSRF token)
  2. Loops through days 0-6:
     a. POST to /settings/set_day/{day_offset}
     b. GET /film/{movie_slug}.html for that day
     c. Extract showtimes using MoviePageExtractor
  3. Accumulate all showtimes across all 7 days
  4. Schedule MovieDetailJob (once per movie)
  5. Schedule ShowtimeProcessJobs (for all showtimes)

  Benefits:
  - No race conditions (each job has isolated session)
  - All data for one movie collected together
  - Fewer HTTP requests (~15 vs 14+ in old approach)
  - Natural unit of work (movie = one entity)
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.KinoKrakow.{
    Config,
    Extractors.MoviePageExtractor
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    movie_slug = args["movie_slug"]
    movie_title = args["movie_title"]
    source_id = args["source_id"]
    force = args["force"] || false

    Logger.info("""
    🎬 Processing Kino Krakow movie: #{movie_title}
    Slug: #{movie_slug}
    Source ID: #{source_id}
    """)

    # Establish session and fetch showtimes for all 7 days
    with {:ok, {cookies, csrf_token}} <- establish_session(movie_slug),
         {:ok, all_showtimes} <- fetch_all_days(movie_slug, movie_title, cookies, csrf_token) do
      Logger.info("""
      ✅ Movie #{movie_title} processed
      Total showtimes across 7 days: #{length(all_showtimes)}
      """)

      # Find unique movies from showtimes (should just be this one movie)
      # But keeping pattern for consistency with existing architecture
      unique_movies =
        all_showtimes
        |> Enum.map(& &1.movie_slug)
        |> Enum.uniq()

      # Schedule MovieDetailJob (should be just 1) with parent tracking
      movies_scheduled = schedule_movie_detail_jobs(unique_movies, source_id, job_id)

      # Schedule ShowtimeProcessJobs for each showtime with parent tracking
      showtimes_scheduled =
        schedule_showtime_jobs(all_showtimes, source_id, movie_slug, length(unique_movies), force, job_id)

      {:ok,
       %{
         movie_slug: movie_slug,
         showtimes_count: length(all_showtimes),
         unique_movies: length(unique_movies),
         movies_scheduled: movies_scheduled,
         showtimes_scheduled: showtimes_scheduled
       }}
    else
      {:error, reason} ->
        Logger.error("❌ Failed to process movie #{movie_slug}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Establish session by fetching the movie page to get cookies and CSRF token
  defp establish_session(movie_slug) do
    movie_url = "#{Config.base_url()}/film/#{movie_slug}.html"
    headers = [{"User-Agent", Config.user_agent()}]

    Logger.debug("📡 Establishing session for movie: #{movie_slug}")

    case HTTPoison.get(movie_url, headers, timeout: Config.timeout()) do
      {:ok, %{status_code: 200, headers: response_headers, body: html}} ->
        cookies = extract_cookies(response_headers)
        csrf_token = extract_csrf_token(html)

        Logger.debug(
          "✅ Session established (CSRF token: #{String.slice(csrf_token || "none", 0..9)}...)"
        )

        {:ok, {cookies, csrf_token}}

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

  # Extract CSRF token from HTML meta tag
  defp extract_csrf_token(html) do
    case Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html) do
      [_, token] -> token
      _ -> nil
    end
  end

  # Fetch showtimes for all 7 days by looping through day offsets
  defp fetch_all_days(movie_slug, movie_title, cookies, csrf_token) do
    Logger.info("📅 Fetching all 7 days for movie: #{movie_title}")
    Logger.info("   Cookies: #{String.slice(cookies, 0..50)}...")
    Logger.info("   CSRF: #{String.slice(csrf_token, 0..20)}...")

    all_showtimes =
      0..6
      |> Enum.flat_map(fn day_offset ->
        Logger.info("   → Processing day #{day_offset}...")

        case fetch_day_showtimes(movie_slug, movie_title, day_offset, cookies, csrf_token) do
          {:ok, showtimes} ->
            Logger.info("   ✅ Day #{day_offset}: #{length(showtimes)} showtimes")
            showtimes

          {:error, reason} ->
            Logger.warning("   ❌ Day #{day_offset}: Failed - #{inspect(reason)}")
            []
        end
      end)

    Logger.info("📊 Total showtimes collected across all days: #{length(all_showtimes)}")
    {:ok, all_showtimes}
  end

  # Fetch showtimes for a specific day
  defp fetch_day_showtimes(movie_slug, movie_title, day_offset, cookies, csrf_token) do
    base_url = Config.base_url()
    movie_url = "#{base_url}/film/#{movie_slug}.html"

    # Headers for POST request (set day)
    post_headers = [
      {"User-Agent", Config.user_agent()},
      {"Accept", "*/*"},
      {"X-Requested-With", "XMLHttpRequest"},
      {"Referer", movie_url},
      {"X-CSRF-Token", csrf_token},
      {"Cookie", cookies}
    ]

    # 1. Set the day via POST
    set_day_url = "#{base_url}/settings/set_day/#{day_offset}"
    rate_limit_delay()

    case HTTPoison.post(set_day_url, "", post_headers, timeout: Config.timeout()) do
      {:ok, %{status_code: status, headers: response_headers}} when status in [200, 302] ->
        # Extract updated cookies from POST response
        # Rails returns new session cookies when session state changes
        updated_cookies = extract_cookies(response_headers)

        # Use updated cookies for GET request (or fall back to original if none)
        cookies_for_get = if updated_cookies != "", do: updated_cookies, else: cookies

        # Headers for GET request with updated cookies
        get_headers = [
          {"User-Agent", Config.user_agent()},
          {"Cookie", cookies_for_get}
        ]

        # 2. Fetch movie page for this day
        rate_limit_delay()

        case HTTPoison.get(movie_url, get_headers, timeout: Config.timeout()) do
          {:ok, %{status_code: 200, body: html}} ->
            # Extract showtimes using MoviePageExtractor
            case MoviePageExtractor.extract(html, movie_slug, movie_title) do
              {:ok, showtimes} ->
                {:ok, showtimes}

              {:error, reason} ->
                {:error, reason}
            end

          {:ok, %{status_code: status}} ->
            {:error, "HTTP #{status} fetching movie page"}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status} setting day"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Schedule MovieDetailJobs for unique movies
  defp schedule_movie_detail_jobs(movie_slugs, source_id, parent_job_id) do
    Logger.debug("📽️  Scheduling #{length(movie_slugs)} MovieDetailJobs")

    scheduled_jobs =
      movie_slugs
      |> Enum.with_index()
      |> Enum.map(fn {movie_slug, index} ->
        # Stagger job execution with rate limiting
        delay_seconds = index * Config.rate_limit()

        EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob.new(
          %{
            "movie_slug" => movie_slug,
            "source_id" => source_id
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

  # Schedule ShowtimeProcessJobs for each showtime
  defp schedule_showtime_jobs(showtimes, source_id, movie_slug, movie_count, force, parent_job_id) do
    # Calculate delay to give MovieDetailJobs time to complete first
    rate_limit = Config.rate_limit()
    # Ensure movie is cached before showtimes process
    # Need sufficient delay for MovieDetailJob to:
    # 1. Wait in queue (~30-90 seconds depending on load)
    # 2. Execute (fetch movie details from website, ~5-10 seconds)
    # 3. Complete and commit to database
    # Using 120 seconds to be safe
    base_delay = movie_count * rate_limit + 120

    # Add external_ids to showtimes for freshness checking
    showtimes_with_ids =
      Enum.map(showtimes, fn showtime ->
        showtime_map = if is_struct(showtime), do: Map.from_struct(showtime), else: showtime

        # Extract fields for external_id
        movie = showtime_map[:movie_slug] || showtime_map["movie_slug"]
        cinema = showtime_map[:cinema_slug] || showtime_map["cinema_slug"]
        datetime = showtime_map[:datetime] || showtime_map["datetime"]

        # Extract date and time components
        date = DateTime.to_date(datetime) |> Date.to_iso8601()
        time = DateTime.to_time(datetime) |> Time.to_string() |> String.slice(0..4)

        # Generate external_id matching ShowtimeProcessJob pattern
        external_id =
          "kino_krakow_#{movie}_#{cinema}_#{date}_#{time}"
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
    🔄 Kino Krakow Freshness Check: Movie #{movie_slug}
    Processing #{length(showtimes_to_process)}/#{total_showtimes} showtimes #{if force, do: "(Force mode)", else: "(#{skipped} fresh, threshold: #{threshold}h)"}
    """)

    scheduled_jobs =
      showtimes_to_process
      |> Enum.with_index()
      |> Enum.map(fn {showtime, index} ->
        # Stagger job execution (2 seconds between showtimes)
        delay_seconds = base_delay + index * 2

        EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob.new(
          %{
            "showtime" => showtime,
            "source_id" => source_id
          },
          queue: :scraper,
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

  # Rate limiting
  defp rate_limit_delay do
    Process.sleep(Config.rate_limit() * 1000)
  end
end
