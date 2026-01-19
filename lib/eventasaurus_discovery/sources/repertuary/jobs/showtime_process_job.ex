defmodule EventasaurusDiscovery.Sources.Repertuary.Jobs.ShowtimeProcessJob do
  @moduledoc """
  Oban job for processing individual Repertuary.pl showtimes into events.

  Retrieves the matched movie from cache/database, enriches the showtime
  with movie and cinema data, transforms to event format, and processes
  through the unified EventProcessor.

  ## Multi-City Support

  Pass `"city"` in job args to process showtimes for a specific city:

      ShowtimeProcessJob.new(%{
        "showtime" => showtime_data,
        "source_id" => 123,
        "city" => "warszawa"
      }) |> Oban.insert()

  Defaults to "krakow" for backward compatibility.

  If the movie was not successfully matched in MovieDetailJob, the showtime
  is skipped (not an error).
  """

  use Oban.Worker,
    queue: :scraper,
    # Increased max_attempts since snooze doesn't count as an attempt
    # but we want resilience for actual errors
    max_attempts: 5

  require Logger

  # Snooze delay when waiting for MovieDetailJob to complete (30 seconds)
  # This is much better than {:error, :movie_not_ready} because:
  # 1. Snooze doesn't count as an attempt (preserves max_attempts for real errors)
  # 2. Job stays in 'scheduled' state, not 'retryable' (cleaner metrics)
  # 3. Controlled, predictable delay between checks
  @snooze_delay_seconds 30

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor

  alias EventasaurusDiscovery.Sources.Repertuary

  alias EventasaurusDiscovery.Sources.Repertuary.{
    Config,
    Cities,
    Extractors.CinemaExtractor,
    Transformer
  }

  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    showtime = args["showtime"]
    source_id = args["source_id"]
    city = args["city"] || Config.default_city()

    case Cities.get(city) do
      nil ->
        Logger.error("❌ Unknown city: #{city}")
        {:error, :unknown_city}

      city_config ->
        do_perform(job, showtime, source_id, city, city_config)
    end
  end

  defp do_perform(job, showtime, source_id, city, city_config) do
    # CRITICAL: external_id MUST be set by MoviePageJob
    # We do NOT generate it here to avoid drift (BandsInTown A+ pattern)
    external_id = showtime["external_id"]

    result =
      if is_nil(external_id) do
        Logger.error("""
        🚨 CRITICAL: Missing external_id in showtime job args.
        This indicates a bug in MoviePageJob or job serialization.
        Showtime: #{showtime["movie_slug"]} at #{showtime["cinema_slug"]}
        City: #{city_config.name}
        """)

        {:error, :missing_external_id}
      else
        # CRITICAL: Mark event as seen BEFORE processing (BandsInTown pattern)
        # This ensures last_seen_at is updated even if processing fails
        EventProcessor.mark_event_as_seen(external_id, source_id)

        process_showtime(showtime, source_id, city)
      end

    # Track metrics in job metadata
    case result do
      {:ok, _} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:snooze, seconds} = snooze_result ->
        # Snooze doesn't count as an attempt - just waiting for MovieDetailJob
        # Don't record this as success or failure in metrics
        # The job will be rescheduled and try again
        Logger.debug("🔄 Snoozing showtime job for #{seconds}s (waiting for movie)")
        snooze_result

      {:discard, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result

      _other ->
        # Pass through any other return types unchanged
        result
    end
  end

  defp process_showtime(showtime, source_id, city) do
    # City already validated in perform/1, but add fallback for safety
    city_config = Cities.get(city) || Cities.get(Config.default_city())

    Logger.debug(
      "🎫 Processing showtime: #{showtime["movie_slug"]} at #{showtime["cinema_slug"]} (#{city_config.name})"
    )

    # Get movie from database using generic repertuary_slug
    case get_movie(showtime["movie_slug"]) do
      {:ok, movie} ->
        # Movie was successfully matched and stored in database
        process_showtime_with_movie(showtime, movie, source_id, city)

      {:error, :not_found} ->
        # Movie not in database - check if MovieDetailJob completed
        case check_movie_detail_job_status(showtime["movie_slug"], city) do
          :completed_without_match ->
            # MovieDetailJob completed but didn't create movie (TMDB match failed)
            # Skip this showtime (not an error)
            Logger.info(
              "⏭️ Skipping showtime for unmatched movie: #{showtime["movie_slug"]} (#{city_config.name})"
            )

            # Return standardized metadata for skipped items (Phase 3.1)
            {:ok,
             %{
               "job_role" => "processor",
               "pipeline_id" => "repertuary_#{city}_#{Date.utc_today()}",
               "entity_id" => showtime["external_id"] || "unknown",
               "entity_type" => "showtime",
               "city" => city,
               "items_processed" => 0,
               "status" => "skipped",
               "reason" => "movie_unmatched",
               "movie_slug" => showtime["movie_slug"]
             }}

          :not_found_or_pending ->
            # MovieDetailJob hasn't completed yet - use snooze to wait
            # Snooze is better than {:error, :movie_not_ready} because:
            # - Doesn't count as an attempt (preserves retries for real errors)
            # - Job goes to 'scheduled' state, not 'retryable'
            # - Cleaner metrics and more predictable behavior
            Logger.info(
              "⏳ Movie not ready yet, snoozing #{@snooze_delay_seconds}s: #{showtime["movie_slug"]} (#{city_config.name})"
            )

            {:snooze, @snooze_delay_seconds}
        end
    end
  end

  # Process showtime with matched movie
  defp process_showtime_with_movie(showtime, movie, source_id, city) do
    city_config = Cities.get(city)

    # Get cinema data (no HTTP request - just format from slug)
    # Pass city to CinemaExtractor for city-specific context
    cinema_data = CinemaExtractor.extract("", showtime["cinema_slug"], city)

    # Enrich showtime with movie and cinema data
    enriched = enrich_showtime(showtime, movie, cinema_data, city)

    # Transform to event format
    case Transformer.transform_event(enriched, city) do
      {:ok, transformed} ->
        # Get source safely
        case Repo.get(Source, source_id) do
          nil ->
            Logger.error(
              "🚫 Discarding showtime: source #{source_id} not found (#{city_config.name})"
            )

            {:discard, :source_not_found}

          source ->
            # Check for duplicates before processing (pass source struct)
            case check_deduplication(transformed, source, city) do
              {:ok, :unique} ->
                Logger.debug(
                  "✅ Processing unique showtime: #{transformed[:title]} (#{city_config.name})"
                )

                process_event(transformed, source, city)

              {:ok, :skip_duplicate} ->
                Logger.info(
                  "⏭️  Skipping duplicate showtime: #{transformed[:title]} (#{city_config.name})"
                )

                # Still process through Processor to create/update PublicEventSource entry
                process_event(transformed, source, city)

              {:ok, :validation_failed} ->
                Logger.warning(
                  "⚠️ Validation failed, processing anyway: #{transformed[:title]} (#{city_config.name})"
                )

                process_event(transformed, source, city)
            end
        end

      {:error, reason} ->
        Logger.error("❌ Failed to transform showtime: #{inspect(reason)} (#{city_config.name})")
        {:error, reason}
    end
  end

  # Enrich showtime with movie and cinema data
  defp enrich_showtime(showtime, movie, cinema_data, city) do
    # Convert string keys to atoms for consistency
    showtime_map = atomize_keys(showtime)

    # Parse datetime string back to DateTime struct (Oban serializes DateTime to ISO8601 string)
    datetime = parse_datetime(showtime_map[:datetime] || showtime["datetime"])

    showtime_map
    |> Map.put(:datetime, datetime)
    |> Map.put(:city, city)
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

  # Get movie from database by Repertuary.pl slug
  # Movie slugs are consistent across all cities, so we use a generic key
  defp get_movie(movie_slug) do
    # Query movie from database using metadata search
    # MovieDetailJob stores the slug in movie.metadata as "repertuary_slug"
    #
    # IMPORTANT: Use DESC order (newest first) because:
    # - TMDB matching improves over time, newer matches are more accurate
    # - Repertuary.pl may reassign slugs to different movies
    # - Old wrong matches (e.g., "kevin-sam-w-domu" -> "Gabby's Dollhouse") get corrected
    query =
      from(m in EventasaurusDiscovery.Movies.Movie,
        where: fragment("?->>'repertuary_slug' = ?", m.metadata, ^movie_slug),
        order_by: [desc: m.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      movie -> {:ok, movie}
    end
  end

  # Check if MovieDetailJob completed for this movie slug
  # Now city-aware to only check jobs for the same city
  defp check_movie_detail_job_status(movie_slug, city) do
    query =
      from(j in Oban.Job,
        where: j.worker == "EventasaurusDiscovery.Sources.Repertuary.Jobs.MovieDetailJob",
        where: fragment("args->>'movie_slug' = ?", ^movie_slug),
        where: fragment("coalesce(args->>'city', 'krakow') = ?", ^city),
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

  # NOTE: generate_external_id removed - now handled exclusively in DayPageJob
  # This ensures consistency and prevents external_id drift (BandsInTown A+ pattern)
  # If you need to generate external_id, use:
  #   EventasaurusDiscovery.Sources.Repertuary.DedupHandler.generate_external_id(showtime_data)

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

  defp check_deduplication(event_data, source, city) do
    city_config = Cities.get(city)

    # Convert string keys to atom keys for dedup handler
    event_with_atom_keys = atomize_event_data(event_data)

    case Repertuary.deduplicate_event(event_with_atom_keys, source) do
      {:unique, _} ->
        {:ok, :unique}

      {:duplicate, existing} ->
        Logger.info("""
        ⏭️  Skipping duplicate Repertuary.pl event (#{city_config.name})
        New: #{event_data[:title] || event_data["title"]}
        Existing: #{existing.title} (ID: #{existing.id})
        """)

        {:ok, :skip_duplicate}

      {:error, reason} ->
        Logger.warning(
          "⚠️ Deduplication validation failed: #{inspect(reason)} (#{city_config.name})"
        )

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

  defp process_event(transformed, source, city) do
    city_config = Cities.get(city)

    # Process through unified pipeline (matches Cinema City pattern)
    case Processor.process_single_event(transformed, source) do
      {:ok, event} ->
        Logger.debug("✅ Created event: #{event.title} (#{city_config.name})")

        # Return standardized metadata structure for job tracking (Phase 3.1)
        {:ok,
         %{
           "job_role" => "processor",
           "pipeline_id" => "repertuary_#{city}_#{Date.utc_today()}",
           "entity_id" => transformed[:external_id],
           "entity_type" => "showtime",
           "city" => city,
           "items_processed" => 1,
           "event_id" => event.id,
           "event_title" => event.title,
           "status" => "created"
         }}

      {:error, reason} ->
        Logger.error("❌ Failed to process event: #{inspect(reason)} (#{city_config.name})")
        {:error, reason}
    end
  end
end
