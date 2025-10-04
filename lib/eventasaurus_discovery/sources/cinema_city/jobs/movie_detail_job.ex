defmodule EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob do
  @moduledoc """
  Oban job for processing individual Cinema City movies with TMDB matching.

  This job receives film data from CinemaDateJob, matches to TMDB,
  and stores the movie in the database.

  Similar to Kino Krakow's MovieDetailJob but adapted for Cinema City's API data:
  - Film data comes from API (not HTML scraping)
  - Uses Cinema City film_id for tracking
  - Reuses TmdbMatcher for consistent matching logic

  Confidence levels (matching Kino Krakow):
  - High confidence (≥70%): Auto-matched, returns {:ok, %{status: :matched}}
  - Medium confidence (50-69%): Needs review, returns {:error, :tmdb_needs_review}
  - Low confidence (<50%): No match, returns {:error, :tmdb_low_confidence}
  - HTTP/API errors: Returns {:error, reason} which triggers Oban retry

  Each movie's matching status is visible in the Oban dashboard.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher
  alias EventasaurusDiscovery.Movies.MovieStore

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    cinema_city_film_id = args["cinema_city_film_id"]
    film_data = args["film_data"]
    source_id = args["source_id"]

    Logger.info("🎬 Processing Cinema City movie: #{film_data["polish_title"]}")

    # Convert film_data from CinemaDateJob to format expected by TmdbMatcher
    movie_data = normalize_film_data(film_data)

    # Match to TMDB
    case TmdbMatcher.match_movie(movie_data) do
      {:ok, tmdb_id, confidence} when confidence >= 0.60 ->
        # High confidence match (≥70%) or Now Playing fallback match (60-70%) - auto-accept
        match_type = if confidence >= 0.70, do: "standard", else: "now_playing_fallback"

        case TmdbMatcher.find_or_create_movie(tmdb_id) do
          {:ok, movie} ->
            Logger.info(
              "✅ Auto-matched (#{match_type}): #{movie.title} (#{trunc(confidence * 100)}% confidence)"
            )

            # Store Cinema City film_id in movie metadata for later lookups
            store_cinema_city_film_id(movie, cinema_city_film_id, source_id)

            {:ok,
             %{
               status: :matched,
               confidence: confidence,
               movie_id: movie.id,
               cinema_city_film_id: cinema_city_film_id,
               tmdb_id: tmdb_id,
               match_type: match_type
             }}

          {:error, reason} ->
            Logger.error("❌ Failed to create movie #{tmdb_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:needs_review, _movie_data, _candidates} ->
        # Medium confidence (50-69%) - needs manual review
        # Return ERROR so Oban marks as failed and visible in dashboard
        Logger.error(
          "❌ TMDB matching failed - needs review: #{movie_data.polish_title || movie_data.original_title} (50-69% confidence)"
        )

        {:error,
         %{
           reason: :tmdb_needs_review,
           cinema_city_film_id: cinema_city_film_id,
           polish_title: movie_data.polish_title,
           original_title: movie_data.original_title,
           confidence_range: "50-69%"
         }}

      {:error, :low_confidence} ->
        # Low confidence (<50%) - no reliable match
        # Return ERROR so Oban marks as failed and visible in dashboard
        Logger.error(
          "❌ TMDB matching failed - low confidence: #{movie_data.polish_title || movie_data.original_title} (<50%)"
        )

        {:error,
         %{
           reason: :tmdb_low_confidence,
           cinema_city_film_id: cinema_city_film_id,
           polish_title: movie_data.polish_title,
           original_title: movie_data.original_title,
           confidence_range: "<50%"
         }}

      {:error, :missing_title} ->
        Logger.error(
          "❌ TMDB matching failed - missing title for film: #{cinema_city_film_id}"
        )

        {:error, %{reason: :missing_title, cinema_city_film_id: cinema_city_film_id}}

      {:error, :no_results} ->
        # Return ERROR so Oban marks as failed and visible in dashboard
        Logger.error(
          "❌ TMDB matching failed - no results for: #{movie_data.polish_title || movie_data.original_title}"
        )

        {:error,
         %{
           reason: :tmdb_no_results,
           cinema_city_film_id: cinema_city_film_id,
           polish_title: movie_data.polish_title,
           original_title: movie_data.original_title
         }}

      {:error, reason} ->
        # Transient errors (network, TMDB API) - let Oban retry
        Logger.error("❌ TMDB matching error for #{cinema_city_film_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Convert Cinema City film_data to TmdbMatcher format
  defp normalize_film_data(film_data) do
    %{
      polish_title: film_data["polish_title"],
      original_title: nil,
      # TmdbMatcher can work with just Polish title
      year: film_data["release_year"],
      runtime: film_data["runtime"],
      director: nil,
      # Cinema City API doesn't provide director
      country: nil
      # Cinema City API doesn't provide country directly
    }
  end

  # Store Cinema City film_id in movie metadata for later database lookups
  defp store_cinema_city_film_id(movie, cinema_city_film_id, source_id) do
    # Add cinema_city_film_id to movie metadata
    updated_metadata =
      Map.put(movie.metadata || %{}, "cinema_city_film_id", cinema_city_film_id)

    # Also store source_id for tracking
    updated_metadata = Map.put(updated_metadata, "cinema_city_source_id", source_id)

    case MovieStore.update_movie(movie, %{metadata: updated_metadata}) do
      {:ok, _updated_movie} ->
        Logger.debug(
          "💾 Stored Cinema City film_id in movie metadata: #{cinema_city_film_id} -> #{movie.id}"
        )

        :ok

      {:error, changeset} ->
        Logger.error(
          "❌ Failed to store Cinema City film_id in metadata: #{inspect(changeset.errors)}"
        )

        :error
    end
  end
end
