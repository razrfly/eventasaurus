defmodule EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob do
  @moduledoc """
  Oban job for processing individual Cinema City movies with TMDB matching.

  This job receives film data from CinemaDateJob, matches to TMDB,
  and stores the movie in the database.

  Similar to Repertuary's MovieDetailJob but adapted for Cinema City's API data:
  - Film data comes from API (not HTML scraping)
  - Uses Cinema City film_id for tracking
  - Reuses TmdbMatcher for consistent matching logic

  Confidence levels (Phase 3: lowered threshold from 60% to 50%):
  - High confidence (≥70%): Standard match, auto-matched
  - Medium confidence (60-69%): Now Playing fallback match, auto-matched
  - Low-medium confidence (50-59%): Accepted with lower confidence, auto-matched
  - Low confidence (<50%): No reliable match, returns {:error, :tmdb_low_confidence}
  - HTTP/API errors: Returns {:error, reason} which triggers Oban retry

  Each movie's matching status is visible in the Oban dashboard.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    unique: [
      period: 300,
      # Prevent duplicate jobs for the same film_id within 5 minutes
      # This handles the case where multiple cinemas show the same movie
      keys: [:cinema_city_film_id],
      # Keep both states to avoid re-processing discarded matches
      states: [:available, :scheduled, :executing, :retryable, :completed, :discarded]
    ]

  require Logger

  alias EventasaurusDiscovery.Movies.TmdbMatcher
  alias EventasaurusDiscovery.Movies.MovieStore
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    cinema_city_film_id = args["cinema_city_film_id"]
    film_data = args["film_data"]
    source_id = args["source_id"]

    polish_title = film_data["polish_title"]
    release_year = film_data["release_year"]

    Logger.info("🎬 Processing Cinema City movie: #{polish_title} (#{release_year})")

    # Convert film_data from CinemaDateJob to format expected by TmdbMatcher
    movie_data = normalize_film_data(film_data)

    # External ID for tracking
    external_id = "cinema_city_film_#{cinema_city_film_id}"

    # Match to TMDB
    result =
      case TmdbMatcher.match_movie(movie_data) do
        {:ok, tmdb_id, confidence, provider} when confidence >= 0.50 ->
          # Lowered from 0.60 to 0.50 to capture more valid matches
          # Match types:
          # - High confidence (≥70%): Standard match
          # - Medium confidence (60-69%): Now Playing fallback
          # - Low-medium confidence (50-59%): Accepted with lower confidence
          match_type =
            cond do
              confidence >= 0.70 -> "standard"
              confidence >= 0.60 -> "now_playing_fallback"
              true -> "low_confidence_accepted"
            end

          # Pass provider info to find_or_create_movie for tracking
          case TmdbMatcher.find_or_create_movie(tmdb_id, matched_by_provider: provider) do
            {:ok, movie} ->
              # Store Cinema City film_id and provider in movie metadata for later lookups
              # Now returns a detailed result map for observability
              storage_result =
                store_cinema_city_film_id(movie, cinema_city_film_id, source_id, provider)

              # Enhanced logging with storage result
              Logger.info("""
              ✅ Auto-matched (#{match_type}) via #{provider}: #{movie.title}
                 Polish title: #{polish_title}
                 Confidence: #{trunc(confidence * 100)}%
                 TMDB ID: #{tmdb_id}
                 Cinema City ID: #{cinema_city_film_id}
                 Provider: #{provider}
                 Storage: #{storage_result.result} (all IDs: #{inspect(storage_result.all_film_ids)})
              """)

              {:ok,
               %{
                 status: :matched,
                 confidence: confidence,
                 movie_id: movie.id,
                 cinema_city_film_id: cinema_city_film_id,
                 tmdb_id: tmdb_id,
                 match_type: match_type,
                 polish_title: polish_title,
                 matched_by_provider: provider,
                 # New observability fields
                 film_id_storage: storage_result
               }}

            {:error, reason} ->
              Logger.error("❌ Failed to create movie #{tmdb_id}: #{inspect(reason)}")
              {:error, reason}
          end

        {:needs_review, _movie_data, candidates} ->
          # This shouldn't happen now since we accept >= 50% confidence
          # But keep for compatibility with TmdbMatcher behavior
          Logger.warning("""
          ⚠️  TMDB matching needs review (unexpected): #{polish_title} (#{release_year})
             Cinema City ID: #{cinema_city_film_id}
             Candidates found: #{length(candidates)}
             Note: This should be rare with 50% threshold
          """)

          {:error,
           %{
             reason: :tmdb_needs_review,
             cinema_city_film_id: cinema_city_film_id,
             polish_title: polish_title,
             release_year: release_year,
             candidate_count: length(candidates)
           }}

        {:error, :low_confidence} ->
          # Low confidence (<50%) - no reliable match
          Logger.warning("""
          ⏭️  TMDB matching low confidence: #{polish_title} (#{release_year})
             Cinema City ID: #{cinema_city_film_id}
             Confidence: <50%
             This movie will be skipped in ShowtimeProcessJob
          """)

          {:error,
           %{
             reason: :tmdb_low_confidence,
             cinema_city_film_id: cinema_city_film_id,
             polish_title: polish_title,
             release_year: release_year
           }}

        {:error, :missing_title} ->
          Logger.error("""
          ❌ TMDB matching failed - missing title
             Cinema City ID: #{cinema_city_film_id}
          """)

          {:error,
           %{
             reason: :missing_title,
             cinema_city_film_id: cinema_city_film_id
           }}

        {:error, :no_results} ->
          # No results from TMDB
          Logger.warning("""
          ⏭️  TMDB matching - no results: #{polish_title} (#{release_year})
             Cinema City ID: #{cinema_city_film_id}
             This might be a local film or not yet in TMDB
             This movie will be skipped in ShowtimeProcessJob
          """)

          {:error,
           %{
             reason: :tmdb_no_results,
             cinema_city_film_id: cinema_city_film_id,
             polish_title: polish_title,
             release_year: release_year
           }}

        {:error, reason} ->
          # Transient errors (network, TMDB API) - let Oban retry
          Logger.error("""
          ❌ TMDB matching error: #{polish_title} (#{release_year})
             Cinema City ID: #{cinema_city_film_id}
             Error: #{inspect(reason)}
             This job will be retried
          """)

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

  # Convert Cinema City film_data to TmdbMatcher format
  # Enhanced: Extract original English titles from mixed-language titles
  defp normalize_film_data(film_data) do
    polish_title = film_data["polish_title"]
    language_info = film_data["language_info"] || %{}

    # Extract original title from mixed-language titles when possible
    # Example: "Eternity. Wybieram ciebie" → "Eternity" (original), "Wybieram ciebie" (Polish)
    original_title = extract_original_title(polish_title, language_info)

    %{
      polish_title: polish_title,
      original_title: original_title,
      year: film_data["release_year"],
      runtime: film_data["runtime"],
      director: nil,
      # Cinema City API doesn't provide director
      country: nil
      # Cinema City API doesn't provide country directly
    }
  end

  # Extract original English title from mixed-language titles
  # Cinema City often provides titles like "Original Title. Polski Tytuł"
  # We can extract the original English title when:
  # 1. original_language indicates it's an English film
  # 2. Title contains a separator (period, colon, dash)
  #
  # @doc false - Internal function, public for testing only
  def extract_original_title(polish_title, %{"original_language" => "en"})
      when is_binary(polish_title) do
    # Common separators used in Cinema City titles
    # Order matters: try period with space first (most common)
    separators = [". ", ": ", " - ", " – ", " — "]

    # Try each separator
    Enum.reduce_while(separators, nil, fn separator, _acc ->
      case String.split(polish_title, separator, parts: 2) do
        [original_part, _polish_part] ->
          # Found a separator - return the original English part
          {:halt, String.trim(original_part)}

        _ ->
          # No match, try next separator
          {:cont, nil}
      end
    end)
  end

  # If original_language is not "en" or missing, return nil (Polish-only film)
  # @doc false - Internal function, public for testing only
  def extract_original_title(_polish_title, _language_info), do: nil

  # Store Cinema City film_id and matched_by_provider in movie metadata for later database lookups
  # Uses array storage (cinema_city_film_ids) to support multiple language variants of the same movie
  # Example: Avatar has "7148s2r" (Polish) and "7148s2r1" (Ukrainian dubbed)
  # Both point to the same TMDB movie and should have showtimes linked
  #
  # Returns a storage result map for observability:
  # %{stored: true/false, result: "added"|"already_exists"|"migrated"|"error", all_film_ids: [...]}
  defp store_cinema_city_film_id(movie, cinema_city_film_id, source_id, provider) do
    current_metadata = movie.metadata || %{}

    # Get existing film_ids - handle both legacy singular and new array format
    {existing_film_ids, needs_migration} = get_existing_film_ids(current_metadata)

    cond do
      # Film_id already in array - nothing to do
      cinema_city_film_id in existing_film_ids ->
        Logger.debug(
          "💾 Cinema City film_id already in array: #{cinema_city_film_id} -> #{movie.id}"
        )

        %{
          stored: false,
          result: "already_exists",
          all_film_ids: existing_film_ids,
          movie_id: movie.id
        }

      # Add new film_id to array (either new array or append to existing)
      true ->
        new_film_ids = existing_film_ids ++ [cinema_city_film_id]

        updated_metadata =
          current_metadata
          # Remove legacy singular field if migrating
          |> Map.delete("cinema_city_film_id")
          # Store as array
          |> Map.put("cinema_city_film_ids", new_film_ids)
          |> Map.put("cinema_city_source_id", source_id)
          |> maybe_put_provider(provider)

        case MovieStore.update_movie(movie, %{metadata: updated_metadata}) do
          {:ok, _updated_movie} ->
            result_type = if needs_migration, do: "migrated", else: "added"

            if needs_migration do
              Logger.info(
                "💾 Migrated Cinema City film_id to array format: #{inspect(new_film_ids)} -> #{movie.id}"
              )
            else
              Logger.info(
                "💾 Added Cinema City film_id to array: #{cinema_city_film_id} -> #{movie.id} (total: #{length(new_film_ids)})"
              )
            end

            %{
              stored: true,
              result: result_type,
              all_film_ids: new_film_ids,
              movie_id: movie.id,
              provider: provider
            }

          {:error, changeset} ->
            Logger.error(
              "❌ Failed to store Cinema City film_id in metadata: #{inspect(changeset.errors)}"
            )

            %{
              stored: false,
              result: "error",
              all_film_ids: existing_film_ids,
              movie_id: movie.id,
              error: inspect(changeset.errors)
            }
        end
    end
  end

  # Get existing film_ids from metadata, handling both legacy and new formats
  # Returns {list_of_film_ids, needs_migration_flag}
  defp get_existing_film_ids(metadata) do
    cond do
      # New array format - use directly
      is_list(metadata["cinema_city_film_ids"]) ->
        {metadata["cinema_city_film_ids"], false}

      # Legacy singular format - needs migration
      is_binary(metadata["cinema_city_film_id"]) ->
        {[metadata["cinema_city_film_id"]], true}

      # No existing film_ids
      true ->
        {[], false}
    end
  end

  # Only add matched_by_provider if not already set (preserve original match provider)
  defp maybe_put_provider(metadata, nil), do: metadata

  defp maybe_put_provider(metadata, provider) do
    if Map.has_key?(metadata, "matched_by_provider") do
      metadata
    else
      Map.put(metadata, "matched_by_provider", provider)
    end
  end
end
