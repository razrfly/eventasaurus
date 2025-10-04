defmodule EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob do
  @moduledoc """
  Oban job for processing Cinema City events for a specific cinema and date.

  This job is part of a distributed scraping strategy that prevents timeouts
  by breaking up the multi-cinema, multi-day scraping into smaller units of work.

  Each CinemaDateJob:
  1. Fetches film events for a specific cinema on a specific date
  2. Extracts films and showtimes from API response
  3. Identifies unique movies
  4. Schedules MovieDetailJobs for each unique movie
  5. Schedules ShowtimeProcessJobs for each showtime

  This allows for:
  - Better failure isolation (one cinema/date failing doesn't affect others)
  - Concurrent processing of multiple cinema/date combinations
  - More granular progress tracking
  - Ability to resume from partial failures
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.CinemaCity.{
    Client,
    Config,
    Extractors.EventExtractor
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    cinema_data = args["cinema_data"]
    cinema_city_id = args["cinema_city_id"]
    date = args["date"]
    source_id = args["source_id"]

    Logger.info("""
    🎬 Processing Cinema City: #{cinema_data["name"]}
    Date: #{date}
    Cinema ID: #{cinema_city_id}
    """)

    # Fetch film events from API
    case Client.fetch_film_events(cinema_city_id, date) do
      {:ok, %{films: films, events: events}} ->
        if Enum.empty?(films) || Enum.empty?(events) do
          Logger.info("📭 No events for #{cinema_data["name"]} on #{date}")
          {:ok, %{films: 0, events: 0, jobs_scheduled: 0}}
        else
          process_film_events(films, events, cinema_data, cinema_city_id, date, source_id)
        end

      {:error, reason} ->
        Logger.error(
          "❌ Failed to fetch film events for #{cinema_data["name"]} on #{date}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Process films and events
  defp process_film_events(films, events, cinema_data, cinema_city_id, date, source_id) do
    # Extract films
    extracted_films = Enum.map(films, &EventExtractor.extract_film/1)

    # Match films with their events
    matched = EventExtractor.match_films_with_events(films, events)

    # Get unique film IDs
    unique_film_ids =
      extracted_films
      |> Enum.map(& &1.cinema_city_film_id)
      |> Enum.uniq()

    Logger.info("""
    ✅ #{cinema_data["name"]} on #{date}
    Films: #{length(films)}
    Events: #{length(events)}
    Unique films: #{length(unique_film_ids)}
    """)

    # Schedule MovieDetailJobs for unique movies
    movies_scheduled = schedule_movie_detail_jobs(unique_film_ids, extracted_films, source_id)

    # Schedule ShowtimeProcessJobs for each film/event combination
    # These will wait for MovieDetailJobs to complete
    showtimes_scheduled =
      schedule_showtime_jobs(
        matched,
        cinema_data,
        cinema_city_id,
        date,
        source_id,
        length(unique_film_ids)
      )

    {:ok,
     %{
       cinema: cinema_data["name"],
       date: date,
       films_count: length(films),
       events_count: length(events),
       unique_films: length(unique_film_ids),
       movies_scheduled: movies_scheduled,
       showtimes_scheduled: showtimes_scheduled
     }}
  end

  # Schedule MovieDetailJobs for unique movies
  defp schedule_movie_detail_jobs(film_ids, extracted_films, source_id) do
    Logger.info("📽️ Scheduling #{length(film_ids)} MovieDetailJobs")

    # Create a map of film_id -> film_data for quick lookup
    films_map =
      extracted_films
      |> Enum.map(fn film -> {film.cinema_city_film_id, film} end)
      |> Map.new()

    scheduled_jobs =
      film_ids
      |> Enum.map(fn film_id ->
        film_data = Map.get(films_map, film_id)

        # REMOVED scheduled_at staggering to allow Oban unique constraints to work
        # Oban's queue concurrency limits will naturally throttle execution
        EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob.new(
          %{
            "cinema_city_film_id" => film_id,
            "film_data" => film_data,
            "source_id" => source_id
          },
          queue: :scraper_detail
        )
        |> Oban.insert()
      end)

    # Count successful insertions
    Enum.count(scheduled_jobs, fn
      {:ok, _} -> true
      _ -> false
    end)
  end

  # Schedule ShowtimeProcessJobs for each matched film/event
  defp schedule_showtime_jobs(matched, cinema_data, cinema_city_id, date, source_id, movie_count) do
    # Calculate delay to give MovieDetailJobs time to complete first
    # Each MovieDetailJob is scheduled with delays based on its index: index * Config.rate_limit()
    # Last movie starts at: (movie_count - 1) * rate_limit
    # Add buffer for movie processing time (API + TMDB matching): ~30 seconds
    rate_limit = Config.rate_limit()
    base_delay = movie_count * rate_limit + 30

    # Flatten matched films with events into individual showtime jobs
    showtimes =
      matched
      |> Enum.flat_map(fn %{film: film, events: events} ->
        Enum.map(events, fn event ->
          %{film: film, event: event}
        end)
      end)

    scheduled_jobs =
      showtimes
      |> Enum.map(fn %{film: film, event: event} ->
        # Extract event_id BEFORE putting event into showtime_data
        # event is a map with atom keys from EventExtractor
        cinema_city_event_id = event[:cinema_city_event_id]

        # Combine film and event data for ShowtimeProcessJob
        showtime_data = %{
          "film" => film,
          "event" => event,
          "cinema_data" => cinema_data,
          "cinema_city_id" => cinema_city_id,
          "date" => date
        }

        # REMOVED scheduled_at staggering to allow Oban unique constraints to work
        # Oban's queue concurrency limits will naturally throttle execution
        EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob.new(
          %{
            "cinema_city_event_id" => cinema_city_event_id,
            "showtime" => showtime_data,
            "source_id" => source_id
          },
          queue: :scraper
        )
        |> Oban.insert()
      end)

    # Count successful insertions
    Enum.count(scheduled_jobs, fn
      {:ok, _} -> true
      _ -> false
    end)
  end
end
