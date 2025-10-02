defmodule EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob do
  @moduledoc """
  Oban job for processing individual Kino Krakow movie details.

  Fetches the movie detail page, extracts metadata, matches to TMDB,
  and stores the movie in the database.

  This job provides granular visibility into TMDB matching success/failure:
  - High confidence (≥80%): Auto-matched, returns {:ok, %{status: :matched}}
  - Medium confidence (60-79%): Needs review, returns {:ok, %{status: :needs_review}}
  - Low confidence (<60%): No match, returns {:ok, %{status: :no_match}}
  - HTTP/API errors: Returns {:error, reason} which triggers Oban retry

  Each movie's matching status is visible in the Oban dashboard.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.KinoKrakow.{
    Config,
    Extractors.MovieExtractor,
    TmdbMatcher
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    movie_slug = args["movie_slug"]
    source_id = args["source_id"]

    Logger.info("🎬 Processing movie: #{movie_slug}")

    # Fetch movie detail page
    url = Config.movie_detail_url(movie_slug)
    headers = [{"User-Agent", Config.user_agent()}]

    case HTTPoison.get(url, headers, timeout: Config.timeout()) do
      {:ok, %{status_code: 200, body: html}} ->
        process_movie_html(html, movie_slug, source_id)

      {:ok, %{status_code: 404}} ->
        Logger.warning("⚠️ Movie page not found: #{movie_slug}")
        {:ok, %{status: :not_found, movie_slug: movie_slug}}

      {:ok, %{status_code: status}} ->
        Logger.error("❌ HTTP #{status} for movie: #{movie_slug}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch movie #{movie_slug}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Process movie HTML and match to TMDB
  defp process_movie_html(html, movie_slug, _source_id) do
    # Extract movie metadata
    movie_data = MovieExtractor.extract(html)

    Logger.debug("📋 Extracted movie data: #{movie_data.polish_title || movie_data.original_title}")

    # Match to TMDB
    case TmdbMatcher.match_movie(movie_data) do
      {:ok, tmdb_id, confidence} when confidence >= 0.80 ->
        # High confidence match - auto-accept
        case TmdbMatcher.find_or_create_movie(tmdb_id) do
          {:ok, movie} ->
            Logger.info("✅ Auto-matched: #{movie.title} (#{trunc(confidence * 100)}% confidence)")

            # Store Kino Krakow slug in movie metadata for later lookups
            store_kino_krakow_slug(movie, movie_slug)

            {:ok, %{
              status: :matched,
              confidence: confidence,
              movie_id: movie.id,
              movie_slug: movie_slug,
              tmdb_id: tmdb_id
            }}

          {:error, reason} ->
            Logger.error("❌ Failed to create movie #{tmdb_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:needs_review, _movie_data, _candidates} ->
        # Medium confidence (60-79%) - needs manual review
        # Return ERROR so Oban marks as failed and visible in dashboard
        Logger.error("❌ TMDB matching failed - needs review: #{movie_data.polish_title || movie_data.original_title} (60-79% confidence)")

        {:error, %{
          reason: :tmdb_needs_review,
          movie_slug: movie_slug,
          polish_title: movie_data.polish_title,
          original_title: movie_data.original_title,
          confidence_range: "60-79%"
        }}

      {:error, :low_confidence} ->
        # Low confidence (<60%) - no reliable match
        # Return ERROR so Oban marks as failed and visible in dashboard
        Logger.error("❌ TMDB matching failed - low confidence: #{movie_data.polish_title || movie_data.original_title} (<60%)")

        {:error, %{
          reason: :tmdb_low_confidence,
          movie_slug: movie_slug,
          polish_title: movie_data.polish_title,
          original_title: movie_data.original_title,
          confidence_range: "<60%"
        }}

      {:error, :missing_title} ->
        Logger.error("❌ TMDB matching failed - missing title for movie: #{movie_slug}")
        {:error, %{reason: :missing_title, movie_slug: movie_slug}}

      {:error, :no_results} ->
        # Return ERROR so Oban marks as failed and visible in dashboard
        Logger.error("❌ TMDB matching failed - no results for: #{movie_data.polish_title || movie_data.original_title}")

        {:error, %{
          reason: :tmdb_no_results,
          movie_slug: movie_slug,
          polish_title: movie_data.polish_title,
          original_title: movie_data.original_title
        }}

      {:error, reason} ->
        # Transient errors (network, TMDB API) - let Oban retry
        Logger.error("❌ TMDB matching error for #{movie_slug}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Store Kino Krakow slug in movie metadata for later database lookups
  defp store_kino_krakow_slug(movie, kino_slug) do
    # Add kino_krakow_slug to movie metadata
    updated_metadata = Map.put(movie.metadata || %{}, "kino_krakow_slug", kino_slug)

    case EventasaurusDiscovery.Movies.MovieStore.update_movie(movie, %{metadata: updated_metadata}) do
      {:ok, _updated_movie} ->
        Logger.debug("💾 Stored Kino Krakow slug in movie metadata: #{kino_slug} -> #{movie.id}")
        :ok

      {:error, changeset} ->
        Logger.error("❌ Failed to store Kino Krakow slug in metadata: #{inspect(changeset.errors)}")
        :error
    end
  end
end
