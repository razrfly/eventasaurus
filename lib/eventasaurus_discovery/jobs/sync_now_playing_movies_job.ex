defmodule EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob do
  @moduledoc """
  Oban job for syncing "Now Playing" movies from TMDB to pre-populate the movies table.

  This job:
  1. Fetches current cinema releases from TMDB's "Now Playing" endpoint for a specific region
  2. For each movie, fetches translations to get localized titles (e.g., Polish)
  3. Creates or updates movies in the database with full TMDB metadata
  4. Stores translations in metadata.translations for fallback matching

  This enables the TMDB matcher to use a pre-populated list of current releases
  as a fallback when fuzzy matching fails, improving match accuracy from 71% to 85%+.

  ## Usage

      # Via Mix task
      mix tmdb.sync_now_playing --region PL --pages 3

      # Via Oban (programmatic)
      EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob.new(%{region: "PL", pages: 3})
      |> Oban.insert()

      # Future: Via cron (daily at 3 AM)
      # config :eventasaurus_app, Oban,
      #   plugins: [
      #     {Oban.Plugins.Cron,
      #       crontab: [
      #         {"0 3 * * *", EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob, args: %{region: "PL"}}
      #       ]
      #     }
      #   ]
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3

  require Logger

  alias EventasaurusWeb.Services.TmdbService
  alias EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    region = normalize_region(args["region"] || args[:region])
    pages = coerce_pages(args["pages"] || args[:pages])

    Logger.info("🎬 Starting Now Playing sync for region: #{region} (#{pages} pages)")

    # Fetch and sync movies from multiple pages
    results =
      for page <- 1..pages do
        fetch_and_sync_page(region, page)
      end

    total_synced = Enum.sum(results)
    Logger.info("✅ Synced #{total_synced} now playing movies for #{region}")

    {:ok, %{region: region, pages: pages, movies_synced: total_synced}}
  end

  # Fetch a single page of now playing movies and sync them
  defp fetch_and_sync_page(region, page) do
    Logger.info("📄 Fetching now playing page #{page} for #{region}")

    case TmdbService.get_now_playing(region, page) do
      {:ok, movies} ->
        Logger.info("Found #{length(movies)} movies on page #{page}")

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

      {:error, reason} ->
        Logger.error("Failed to fetch now playing page #{page}: #{inspect(reason)}")
        0
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
          Logger.warning(
            "Failed to fetch translations for movie #{tmdb_id}: #{inspect(reason)}"
          )

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

  # Normalize region code to uppercase 2-letter ISO code
  defp normalize_region(nil), do: "PL"
  defp normalize_region(region) when is_binary(region) do
    region
    |> String.upcase()
    |> case do
      <<a, b>> when a in ?A..?Z and b in ?A..?Z -> <<a, b>>
      _ -> "PL"
    end
  end
  defp normalize_region(_), do: "PL"

  # Coerce pages parameter to valid positive integer
  defp coerce_pages(nil), do: 3
  defp coerce_pages(p) when is_integer(p) and p > 0 and p <= 20, do: p
  defp coerce_pages(p) when is_integer(p) and p > 20, do: 20  # Cap at 20 pages
  defp coerce_pages(p) when is_binary(p) do
    case Integer.parse(p) do
      {i, ""} when i > 0 and i <= 20 -> i
      {i, ""} when i > 20 -> 20  # Cap at 20 pages
      _ -> 3
    end
  end
  defp coerce_pages(_), do: 3

  # Deep merge metadata to preserve existing data
  defp deep_merge_metadata(existing, incoming) do
    # Union now_playing_regions (deduplicated)
    existing_regions = Map.get(existing, "now_playing_regions", [])
    incoming_regions = Map.get(incoming, "now_playing_regions", [])
    merged_regions = Enum.uniq(existing_regions ++ incoming_regions)

    # Deep merge translations by locale
    existing_translations = Map.get(existing, "translations", %{})
    incoming_translations = Map.get(incoming, "translations", %{})
    merged_translations = Map.merge(existing_translations, incoming_translations, fn _locale, v1, v2 ->
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
    |> Map.put("first_seen_in_theaters", existing_first_seen || Map.get(incoming, "first_seen_in_theaters"))
    |> Map.put("last_synced_at", DateTime.utc_now() |> DateTime.to_iso8601())
  end
end
