defmodule EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob do
  @moduledoc """
  Oban job for processing individual Kino Krakow showtimes into events.

  Retrieves the matched movie from cache/database, enriches the showtime
  with movie and cinema data, transforms to event format, and processes
  through the unified EventProcessor.

  If the movie was not successfully matched in MovieDetailJob, the showtime
  is skipped (not an error).
  """

  use Oban.Worker,
    queue: :scraper,
    max_attempts: 3

  require Logger

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor

  alias EventasaurusDiscovery.Sources.KinoKrakow.{
    Extractors.CinemaExtractor,
    Transformer
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    showtime = args["showtime"]
    source_id = args["source_id"]

    # Generate external_id for this showtime
    external_id = generate_external_id(showtime)

    # CRITICAL: Mark event as seen BEFORE processing (BandsInTown pattern)
    # This ensures last_seen_at is updated even if processing fails
    EventProcessor.mark_event_as_seen(external_id, source_id)

    Logger.debug("🎫 Processing showtime: #{showtime["movie_slug"]} at #{showtime["cinema_slug"]}")

    # Get movie from database
    case get_movie(showtime["movie_slug"]) do
      {:ok, movie} ->
        # Movie was successfully matched and stored in database
        process_showtime_with_movie(showtime, movie, source_id)

      {:error, :not_found} ->
        # Movie not in database - check if MovieDetailJob completed
        case check_movie_detail_job_status(showtime["movie_slug"]) do
          :completed_without_match ->
            # MovieDetailJob completed but didn't create movie (TMDB match failed)
            # Skip this showtime (not an error)
            Logger.info("⏭️ Skipping showtime for unmatched movie: #{showtime["movie_slug"]}")
            {:ok, :skipped}

          :not_found_or_pending ->
            # MovieDetailJob hasn't completed yet - retry
            Logger.warning(
              "⏳ Movie not found in database yet, will retry: #{showtime["movie_slug"]}"
            )

            {:error, :movie_not_ready}
        end
    end
  end

  # Process showtime with matched movie
  defp process_showtime_with_movie(showtime, movie, source_id) do
    # Get cinema data (no HTTP request - just format from slug)
    cinema_data = CinemaExtractor.extract("", showtime["cinema_slug"])

    # Enrich showtime with movie and cinema data
    enriched = enrich_showtime(showtime, movie, cinema_data)

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

  # Enrich showtime with movie and cinema data
  defp enrich_showtime(showtime, movie, cinema_data) do
    # Convert string keys to atoms for consistency
    showtime_map = atomize_keys(showtime)

    # Parse datetime string back to DateTime struct (Oban serializes DateTime to ISO8601 string)
    datetime = parse_datetime(showtime_map[:datetime] || showtime["datetime"])

    showtime_map
    |> Map.put(:datetime, datetime)
    |> Map.merge(%{
      movie_id: movie.id,
      tmdb_id: movie.tmdb_id,
      original_title: movie.original_title,
      movie_title: movie.title,
      runtime: movie.runtime,
      poster_url: movie.poster_url,
      backdrop_url: movie.backdrop_url,
      cinema_data: cinema_data
    })
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

  # Get movie from database by Kino Krakow slug
  defp get_movie(movie_slug) do
    # Query movie from database using metadata search
    # MovieDetailJob stores the Kino Krakow slug in movie.metadata
    query =
      from(m in EventasaurusDiscovery.Movies.Movie,
        where: fragment("?->>'kino_krakow_slug' = ?", m.metadata, ^movie_slug)
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      movie -> {:ok, movie}
    end
  end

  # Check if MovieDetailJob completed for this movie slug
  defp check_movie_detail_job_status(movie_slug) do
    query =
      from(j in Oban.Job,
        where: j.worker == "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob",
        where: fragment("args->>'movie_slug' = ?", ^movie_slug),
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
  defp generate_external_id(showtime) do
    # Use movie_slug + cinema_slug + time to create unique ID
    movie = showtime["movie_slug"]
    cinema = showtime["cinema_slug"]
    time = showtime["time"]
    date = showtime["date"] || Date.utc_today() |> Date.to_iso8601()

    "kino_krakow_#{movie}_#{cinema}_#{date}_#{time}"
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
  end

  # Convert string keys to atom keys
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    ArgumentError ->
      # If atom doesn't exist, keep as string keys
      map
  end
end
