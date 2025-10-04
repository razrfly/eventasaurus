defmodule EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob do
  @moduledoc """
  Oban job for processing individual Cinema City showtimes into events.

  Retrieves the matched movie from cache/database, enriches the showtime
  with movie and cinema data, transforms to event format, and processes
  through the unified EventProcessor.

  Similar to Kino Krakow's ShowtimeProcessJob but adapted for Cinema City:
  - Uses cinema_city_film_id to look up movies
  - Cinema data comes from CinemaDateJob args
  - Event data comes directly from API (no HTML scraping)

  If the movie was not successfully matched in MovieDetailJob, the showtime
  is skipped (not an error).
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3,
    unique: [
      period: 300,
      # Prevent duplicate jobs for the same showtime within 5 minutes
      # Use cinema_city_event_id as unique key since each showtime has unique ID
      keys: [:cinema_city_event_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Sources.CinemaCity.Transformer

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    showtime = args["showtime"]
    source_id = args["source_id"]

    film = showtime["film"]
    event = showtime["event"]
    cinema_data = showtime["cinema_data"]
    cinema_city_film_id = film["cinema_city_film_id"]

    # Generate external_id for this showtime
    external_id = generate_external_id(event, cinema_data)

    # CRITICAL: Mark event as seen BEFORE processing (BandsInTown pattern)
    # This ensures last_seen_at is updated even if processing fails
    EventProcessor.mark_event_as_seen(external_id, source_id)

    Logger.debug(
      "🎫 Processing showtime: #{film["polish_title"]} at #{cinema_data["name"]}"
    )

    # Get movie from database
    case get_movie(cinema_city_film_id) do
      {:ok, movie} ->
        # Movie was successfully matched and stored in database
        process_showtime_with_movie(showtime, movie, source_id)

      {:error, :not_found} ->
        # Movie not in database - check if MovieDetailJob completed
        case check_movie_detail_job_status(cinema_city_film_id) do
          :completed_without_match ->
            # MovieDetailJob completed but didn't create movie (TMDB match failed)
            # Skip this showtime (not an error)
            Logger.info("⏭️ Skipping showtime for unmatched movie: #{film["polish_title"]}")
            {:ok, :skipped}

          :not_found_or_pending ->
            # MovieDetailJob hasn't completed yet - retry
            Logger.warning(
              "⏳ Movie not found in database yet, will retry: #{film["polish_title"]}"
            )

            {:error, :movie_not_ready}
        end
    end
  end

  # Process showtime with matched movie
  defp process_showtime_with_movie(showtime, movie, source_id) do
    # Enrich showtime with movie data
    enriched = enrich_showtime(showtime, movie)

    # Transform to event format
    case Transformer.transform_event(enriched) do
      {:ok, transformed} ->
        # Get source
        source = Repo.get!(Source, source_id)

        # Process through unified pipeline
        case Processor.process_single_event(transformed, source) do
          {:ok, event} ->
            Logger.debug("✅ Created event: #{event.title}")
            {:ok, event}

          {:error, reason} ->
            Logger.error("❌ Failed to process event: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to transform showtime: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Enrich showtime with movie data
  defp enrich_showtime(showtime, movie) do
    event = showtime["event"]
    film = showtime["film"]
    cinema_data = showtime["cinema_data"]

    # Parse showtime DateTime (Oban serializes DateTime to ISO8601 string)
    showtime_dt = parse_datetime(event["showtime"])

    %{
      # Event-specific data
      external_id: generate_external_id(event, cinema_data),
      showtime: showtime_dt,
      auditorium: event["auditorium"],
      booking_url: event["booking_url"],
      cinema_city_event_id: event["cinema_city_event_id"],
      # Movie data
      movie_id: movie.id,
      tmdb_id: movie.tmdb_id,
      original_title: movie.original_title,
      movie_title: movie.title,
      runtime: movie.runtime,
      poster_url: movie.poster_url,
      backdrop_url: movie.backdrop_url,
      # Film metadata
      language_info: film["language_info"],
      format_info: film["format_info"],
      genre_tags: film["genre_tags"],
      # Cinema data
      cinema_data: cinema_data
    }
  end

  # Parse datetime from string or return as-is if already DateTime
  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, _} ->
        Logger.error("Failed to parse datetime: #{datetime_string}")
        DateTime.utc_now()
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()

  # Get movie from database by Cinema City film_id
  defp get_movie(cinema_city_film_id) do
    # Query movie from database using metadata search
    # MovieDetailJob stores the cinema_city_film_id in movie.metadata
    query =
      from(m in EventasaurusDiscovery.Movies.Movie,
        where: fragment("?->>'cinema_city_film_id' = ?", m.metadata, ^cinema_city_film_id)
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      movie -> {:ok, movie}
    end
  end

  # Check if MovieDetailJob completed for this film_id
  defp check_movie_detail_job_status(cinema_city_film_id) do
    query =
      from(j in Oban.Job,
        where: j.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
        where: fragment("args->>'cinema_city_film_id' = ?", ^cinema_city_film_id),
        select: %{state: j.state, id: j.id},
        order_by: [desc: j.id],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        # MovieDetailJob hasn't been created yet
        :not_found_or_pending

      %{state: "completed"} ->
        # Completed but movie not in database = TMDB matching succeeded but didn't create movie
        # This shouldn't happen anymore, but handle it
        :completed_without_match

      %{state: state} when state in ["discarded"] ->
        # MovieDetailJob failed permanently - skip this showtime
        :completed_without_match

      %{state: state} when state in ["retryable"] ->
        # MovieDetailJob is still retrying - wait for it
        :not_found_or_pending

      %{state: _other} ->
        # Still executing, available, scheduled, etc.
        :not_found_or_pending
    end
  end

  # Generate external_id for showtime
  defp generate_external_id(event, cinema_data) do
    # Use cinema_city_event_id + cinema_city_id for unique ID
    event_id = event["cinema_city_event_id"]
    cinema_id = cinema_data["cinema_city_id"]

    "cinema_city_#{cinema_id}_#{event_id}"
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
  end
end
