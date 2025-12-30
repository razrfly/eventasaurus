defmodule EventasaurusDiscovery.Jobs.FetchNowPlayingPageJob do
  @moduledoc """
  Atomic worker job for fetching a single page of "Now Playing" movies from TMDB.

  This job is spawned by `SyncNowPlayingMoviesJob` (coordinator) and handles:
  - Fetching one specific page from TMDB's "Now Playing" endpoint
  - Fetching translations for each movie
  - Creating/updating movies in the database
  - Proper error handling with rate limit detection
  - Custom backoff strategies

  ## Architecture

  This is part of a hierarchical job structure with **staggered execution**:
  - **Coordinator**: `SyncNowPlayingMoviesJob` - spawns page jobs with 3s delays
  - **Worker**: `FetchNowPlayingPageJob` (this job) - fetches single page

  **Rate Limit Prevention**:
  - Coordinator staggers jobs by 3 seconds each
  - Prevents concurrent API calls that trigger rate limits
  - Example: Page 1 runs at 0s, Page 2 at 3s, Page 3 at 6s, etc.
  - Result: No rate limit errors under normal operation

  **Benefits of This Architecture**:
  - Each page fetch is independently retryable
  - Rate limit on page 3 doesn't block pages 1-2
  - Clear visibility: each page is a separate job in Oban
  - Smarter retries: only failed pages retry
  - Staggered execution prevents rate limits

  ## Usage

      # Usually spawned by coordinator with staggered scheduling:
      EventasaurusDiscovery.Jobs.FetchNowPlayingPageJob.new(
        %{region: "PL", page: 3, coordinator_job_id: 12345},
        schedule_in: 6  # 3s delay per page
      )
      |> Oban.insert()

      # Can also run directly (not recommended):
      EventasaurusDiscovery.Jobs.FetchNowPlayingPageJob.new(%{
        region: "PL",
        page: 3,
        coordinator_job_id: 12345
      })
      |> Oban.insert()

  ## Error Handling

  - **Rate Limits**: Returns `{:error, :rate_limited}` with 5-minute backoff
  - **Other Errors**: Returns `{:error, reason}` with exponential backoff
  - **Success**: Returns `{:ok, %{page: page, movies_synced: count}}`
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 5

  require Logger

  alias EventasaurusWeb.Services.TmdbService
  alias EventasaurusDiscovery.Movies.TmdbMatcher
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    region = args["region"]
    page = args["page"]
    coordinator_job_id = args["coordinator_job_id"]
    external_id = "now_playing_page_#{region}_#{page}_#{Date.utc_today()}"

    Logger.info(
      "📄 Fetching now playing page #{page} for #{region} (coordinator: #{coordinator_job_id})"
    )

    case TmdbService.get_now_playing(region, page) do
      {:ok, movies} ->
        Logger.info("Found #{length(movies)} movies on page #{page}")

        # Sync all movies and count successes
        synced_count =
          Enum.reduce(movies, 0, fn movie_data, count ->
            case sync_movie_with_translations(movie_data, region) do
              {:ok, _movie} ->
                count + 1

              {:error, reason} ->
                Logger.warning(
                  "Failed to sync movie #{movie_data["id"]} (#{movie_data["title"]}): #{inspect(reason)}"
                )

                count
            end
          end)

        Logger.info(
          "✅ Synced #{synced_count}/#{length(movies)} movies from page #{page} for #{region}"
        )

        MetricsTracker.record_success(job, external_id, %{
          page: page,
          region: region,
          movies_synced: synced_count,
          movies_found: length(movies)
        })

        {:ok, %{page: page, region: region, movies_synced: synced_count}}

      {:error, reason} ->
        # Check if this is a rate limit error
        rate_limited? =
          reason
          |> to_string()
          |> String.downcase()
          |> String.contains?("rate limit")

        if rate_limited? do
          Logger.error(
            "❌ Page #{page} failed: Rate limit exceeded (coordinator: #{coordinator_job_id})"
          )

          MetricsTracker.record_failure(job, :rate_limited, external_id, %{
            page: page,
            region: region,
            error_category: :rate_limited
          })

          {:error, :rate_limited}
        else
          Logger.error(
            "❌ Page #{page} failed: #{inspect(reason)} (coordinator: #{coordinator_job_id})"
          )

          MetricsTracker.record_failure(job, reason, external_id, %{
            page: page,
            region: region,
            error_category: :api_error
          })

          {:error, reason}
        end
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt, unsaved_error: unsaved_error}) do
    # Check if the error was due to rate limiting
    rate_limited? =
      case unsaved_error do
        %{reason: reason} when is_binary(reason) ->
          reason
          |> String.downcase()
          |> String.contains?("rate limit")

        %{reason: :rate_limited} ->
          true

        _ ->
          false
      end

    if rate_limited? do
      # For rate limits, use a fixed 5-minute backoff
      # This gives TMDB API time to reset the rate limit
      :timer.minutes(5)
    else
      # For other errors, use exponential backoff with jitter
      # Formula: attempt^4 + 15 + random(0..30*attempt)
      base_delay = trunc(:math.pow(attempt, 4) + 15)
      jitter = :rand.uniform(30 * attempt)
      base_delay + jitter
    end
  end

  # Sync a single movie with its translations
  defp sync_movie_with_translations(movie_data, region) do
    tmdb_id = movie_data["id"]

    Logger.debug("Syncing movie #{tmdb_id}: #{movie_data["title"]}")

    # Fetch translations to get localized titles
    translations =
      case TmdbService.get_movie_translations(tmdb_id) do
        {:ok, trans} ->
          trans

        {:error, reason} ->
          Logger.warning("Failed to fetch translations for movie #{tmdb_id}: #{inspect(reason)}")
          %{}
      end

    # Build metadata with all TMDB data + translations
    metadata = build_metadata(movie_data, translations, region)

    # Create or update movie using TmdbMatcher's find_or_create_movie
    # This handles the upsert logic and slug generation
    case TmdbMatcher.find_or_create_movie(tmdb_id) do
      {:ok, movie} ->
        # Deep merge metadata to preserve existing translations and regions
        updated_metadata = deep_merge_metadata(movie.metadata || %{}, metadata)

        case EventasaurusDiscovery.Movies.MovieStore.update_movie(movie, %{
               metadata: updated_metadata
             }) do
          {:ok, updated_movie} ->
            Logger.debug("✅ Synced: #{updated_movie.title} (#{tmdb_id})")
            {:ok, updated_movie}

          {:error, changeset} ->
            Logger.error(
              "Failed to update movie metadata #{tmdb_id}: #{inspect(changeset.errors)}"
            )

            {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("Failed to create/find movie #{tmdb_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Build metadata structure for storing in movies.metadata field
  defp build_metadata(movie_data, translations, region) do
    # Extract existing now_playing_regions or initialize empty list
    existing_regions = []

    # Add current region if not already present
    updated_regions =
      if region in existing_regions do
        existing_regions
      else
        [region | existing_regions]
      end

    %{
      "tmdb_data" => extract_tmdb_metadata(movie_data),
      "translations" => translations,
      "now_playing_regions" => updated_regions,
      "first_seen_in_theaters" => Date.utc_today() |> Date.to_string(),
      "last_synced_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  # Extract relevant TMDB metadata from now_playing response
  defp extract_tmdb_metadata(movie_data) do
    %{
      "popularity" => movie_data["popularity"],
      "vote_average" => movie_data["vote_average"],
      "vote_count" => movie_data["vote_count"],
      "genre_ids" => movie_data["genre_ids"] || [],
      "adult" => movie_data["adult"],
      "original_language" => movie_data["original_language"],
      "original_title" => movie_data["original_title"],
      "backdrop_path" => movie_data["backdrop_path"],
      "poster_path" => movie_data["poster_path"]
    }
  end

  # Deep merge metadata to preserve existing data
  defp deep_merge_metadata(existing, incoming) do
    # Union now_playing_regions (deduplicated)
    existing_regions = Map.get(existing, "now_playing_regions", [])
    incoming_regions = Map.get(incoming, "now_playing_regions", [])
    merged_regions = Enum.uniq(existing_regions ++ incoming_regions)

    # Deep merge translations by locale
    existing_translations = Map.get(existing, "translations", %{})
    incoming_translations = Map.get(incoming, "translations", %{})

    merged_translations =
      Map.merge(existing_translations, incoming_translations, fn _locale, v1, v2 ->
        # If both values are maps, merge them; otherwise prefer incoming
        if is_map(v1) and is_map(v2), do: Map.merge(v1, v2), else: v2
      end)

    # Preserve first_seen_in_theaters if it exists
    existing_first_seen = Map.get(existing, "first_seen_in_theaters")

    # Merge base metadata, preserving nested maps
    existing
    |> Map.merge(incoming, fn
      "tmdb_data", v1, v2 when is_map(v1) and is_map(v2) -> Map.merge(v1, v2)
      _key, _v1, v2 -> v2
    end)
    |> Map.put("translations", merged_translations)
    |> Map.put("now_playing_regions", merged_regions)
    |> Map.put(
      "first_seen_in_theaters",
      existing_first_seen || Map.get(incoming, "first_seen_in_theaters")
    )
    |> Map.put("last_synced_at", DateTime.utc_now() |> DateTime.to_iso8601())
  end
end
