defmodule EventasaurusDiscovery.Sources.CinemaCity.Jobs.ShowtimeProcessJob do
  @moduledoc """
  Oban job for processing individual Cinema City showtimes into events.

  Retrieves the matched movie from cache/database, enriches the showtime
  with movie and cinema data, transforms to event format, and processes
  through the unified EventProcessor.

  Similar to Repertuary's ShowtimeProcessJob but adapted for Cinema City:
  - Uses cinema_city_film_id to look up movies
  - Cinema data comes from CinemaDateJob args
  - Event data comes directly from API (no HTML scraping)

  ## Movie Dependency Handling

  This job depends on MovieDetailJob completing first to create the movie record.
  Instead of using `{:error, :movie_not_ready}` which would consume retry attempts,
  we use Oban's `{:snooze, seconds}` pattern:

  - If movie isn't ready yet: `{:snooze, 30}` - reschedules without consuming an attempt
  - If MovieDetailJob failed (discarded): `{:cancel, :movie_not_matched}` - skip showtime
  - If movie is found: process normally

  This prevents the "retryable" state accumulation and preserves max_attempts
  for actual errors (network issues, database problems, etc.).

  If the movie was not successfully matched in MovieDetailJob, the showtime
  is skipped (not an error).
  """

  use Oban.Worker,
    queue: :scraper,
    # Increased max_attempts since snooze doesn't count as an attempt
    # but we want resilience for actual errors
    max_attempts: 5,
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
  alias EventasaurusDiscovery.Sources.CinemaCity
  alias EventasaurusDiscovery.Sources.CinemaCity.Transformer
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    showtime = args["showtime"]
    source_id = args["source_id"]

    film = showtime["film"]
    cinema_data = showtime["cinema_data"]
    cinema_city_film_id = film["cinema_city_film_id"]

    # CRITICAL: external_id MUST be set by CinemaDateJob
    # We do NOT generate it here to avoid drift (BandsInTown A+ pattern)
    external_id = showtime["external_id"]

    result =
      if is_nil(external_id) do
        Logger.error("""
        🚨 CRITICAL: Missing external_id in showtime job args.
        This indicates a bug in CinemaDateJob or job serialization.
        Film: #{film["polish_title"]} at #{cinema_data["name"]}
        """)

        {:error, :missing_external_id}
      else
        # CRITICAL: Mark event as seen BEFORE processing (BandsInTown pattern)
        # This ensures last_seen_at is updated even if processing fails
        EventProcessor.mark_event_as_seen(external_id, source_id)

        process_showtime(showtime, source_id, film, cinema_city_film_id, cinema_data)
      end

    # Track metrics in job metadata
    case result do
      {:ok, :skipped} ->
        # Movie was not matched in TMDB - this is a processing failure
        # Don't call MetricsTracker - let telemetry handler record it as cancelled
        # Telemetry will correctly capture the cancel_reason for metrics categorization
        {:cancel, :movie_not_matched}

      {:ok, _} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:snooze, seconds} = snooze_result ->
        # Snooze doesn't count as an attempt - just waiting for MovieDetailJob
        # Don't record this as success or failure in metrics
        # The job will be rescheduled and try again
        Logger.debug("🔄 Snoozing showtime job for #{seconds}s (waiting for movie)")
        snooze_result

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result

      _other ->
        # Pass through any other return types unchanged (e.g., {:cancel, reason})
        result
    end
  end

  # Snooze delay when waiting for MovieDetailJob to complete (30 seconds)
  # This is much better than {:error, :movie_not_ready} because:
  # 1. Snooze doesn't count as an attempt (preserves max_attempts for real errors)
  # 2. Job stays in 'scheduled' state, not 'retryable' (cleaner metrics)
  # 3. Controlled, predictable delay between checks
  @snooze_delay_seconds 30

  defp process_showtime(showtime, source_id, film, cinema_city_film_id, cinema_data) do
    Logger.debug("🎫 Processing showtime: #{film["polish_title"]} at #{cinema_data["name"]}")

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
            # MovieDetailJob hasn't completed yet - use snooze to wait
            # Snooze is better than {:error, :movie_not_ready} because:
            # - Doesn't count as an attempt (preserves retries for real errors)
            # - Job goes to 'scheduled' state, not 'retryable'
            # - Cleaner metrics and more predictable behavior
            Logger.info(
              "⏳ Movie not ready yet, snoozing #{@snooze_delay_seconds}s: #{film["polish_title"]}"
            )

            {:snooze, @snooze_delay_seconds}
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

        # Check for duplicates before processing (pass source struct)
        case check_deduplication(transformed, source) do
          {:ok, :unique} ->
            Logger.debug("✅ Processing unique showtime: #{transformed[:title]}")
            process_event(transformed, source)

          {:ok, :skip_duplicate} ->
            Logger.info("⏭️  Skipping duplicate showtime: #{transformed[:title]}")
            # Still process through Processor to create/update PublicEventSource entry
            process_event(transformed, source)

          {:ok, :validation_failed} ->
            Logger.warning("⚠️ Validation failed, processing anyway: #{transformed[:title]}")
            process_event(transformed, source)
        end

      {:error, reason} ->
        Logger.error("❌ Failed to transform showtime: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_deduplication(event_data, source) do
    # Convert string keys to atom keys for dedup handler
    event_with_atom_keys = atomize_event_data(event_data)

    case CinemaCity.deduplicate_event(event_with_atom_keys, source) do
      {:unique, _} ->
        {:ok, :unique}

      {:duplicate, existing} ->
        Logger.info("""
        ⏭️  Skipping duplicate Cinema City event
        New: #{event_data[:title] || event_data["title"]}
        Existing: #{existing.title} (ID: #{existing.id})
        """)

        {:ok, :skip_duplicate}

      {:error, reason} ->
        Logger.warning("⚠️ Deduplication validation failed: #{inspect(reason)}")
        # Continue with processing even if dedup fails
        {:ok, :validation_failed}
    end
  end

  # Handle structs (DateTime, Date, etc.) - pass through unchanged
  defp atomize_event_data(%{__struct__: _} = struct), do: struct

  defp atomize_event_data(%{} = data) do
    Enum.reduce(data, %{}, fn {k, v}, acc ->
      key =
        if is_binary(k) do
          try do
            String.to_existing_atom(k)
          rescue
            ArgumentError -> k
          end
        else
          k
        end

      Map.put(acc, key, atomize_event_data(v))
    end)
  end

  defp atomize_event_data(list) when is_list(list) do
    Enum.map(list, &atomize_event_data/1)
  end

  defp atomize_event_data(value), do: value

  defp process_event(transformed, source) do
    # Process through unified pipeline
    case Processor.process_single_event(transformed, source) do
      {:ok, event} ->
        Logger.debug("✅ Created event: #{event.title}")
        {:ok, event}

      {:error, reason} ->
        Logger.error("❌ Failed to process event: #{inspect(reason)}")
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
      # CRITICAL: Reuse external_id from job args (BandsInTown A+ pattern)
      external_id: showtime["external_id"],
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
  # Supports both legacy singular format and new array format:
  # - Legacy: metadata.cinema_city_film_id = "7148s2r"
  # - New: metadata.cinema_city_film_ids = ["7148s2r", "7148s2r1"]
  #
  # This allows Ukrainian dubbed variants (e.g., "7148s2r1") to find the same
  # movie as the Polish version ("7148s2r").
  #
  # Order by inserted_at to get the oldest (most likely correct) movie first
  # in case of duplicates from historical data issues.
  defp get_movie(cinema_city_film_id) do
    # First try the new array format (cinema_city_film_ids contains the film_id)
    # Using JSON array containment operator @> to check if film_id is in the array
    #
    # Note: We use (?::text)::jsonb instead of ?::jsonb because Postgrex sends
    # the parameter as text, and PostgreSQL's direct cast from parameterized text
    # to jsonb doesn't work the same as casting a literal string. The double cast
    # explicitly converts the text parameter to jsonb.
    film_id_json = Jason.encode!([cinema_city_film_id])

    array_query =
      from(m in EventasaurusDiscovery.Movies.Movie,
        where: fragment("?->'cinema_city_film_ids' @> (?::text)::jsonb", m.metadata, ^film_id_json),
        order_by: [asc: m.inserted_at],
        limit: 1
      )

    case Repo.one(array_query) do
      nil ->
        # Fallback to legacy singular format for backward compatibility
        legacy_query =
          from(m in EventasaurusDiscovery.Movies.Movie,
            where: fragment("?->>'cinema_city_film_id' = ?", m.metadata, ^cinema_city_film_id),
            order_by: [asc: m.inserted_at],
            limit: 1
          )

        case Repo.one(legacy_query) do
          nil -> {:error, :not_found}
          movie -> {:ok, movie}
        end

      movie ->
        {:ok, movie}
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

  # NOTE: generate_external_id removed - now handled exclusively in CinemaDateJob
  # This ensures consistency and prevents external_id drift (BandsInTown A+ pattern)
  # If you need to generate external_id, use:
  #   EventasaurusDiscovery.Sources.CinemaCity.DedupHandler.generate_external_id(event_data)
end
