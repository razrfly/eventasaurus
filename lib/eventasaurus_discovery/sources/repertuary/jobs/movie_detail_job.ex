defmodule EventasaurusDiscovery.Sources.Repertuary.Jobs.MovieDetailJob do
  @moduledoc """
  Oban job for processing individual Repertuary.pl movie details.

  Fetches the movie detail page, extracts metadata, matches to TMDB,
  and stores the movie in the database.

  ## Multi-City Support

  Pass `"city"` in job args to fetch from a specific city:

      MovieDetailJob.new(%{
        "movie_slug" => "gladiator-ii",
        "source_id" => 123,
        "city" => "warszawa"
      }) |> Oban.insert()

  Defaults to "krakow" for backward compatibility.

  This job provides granular visibility into TMDB matching success/failure:
  - High confidence (≥70%): Auto-matched, returns {:ok, %{status: :matched}}
  - Medium confidence (50-69%): Needs review, returns {:ok, %{status: :needs_review}}
  - Low confidence (<50%): No match, returns {:ok, %{status: :no_match}}
  - HTTP/API errors: Returns {:error, reason} which triggers Oban retry

  Each movie's matching status is visible in the Oban dashboard.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.Repertuary.{
    Config,
    Cities,
    Extractors.MovieExtractor
  }

  alias EventasaurusDiscovery.Movies.TmdbMatcher

  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    movie_slug = args["movie_slug"]
    source_id = args["source_id"]
    city = args["city"] || Config.default_city()

    case Cities.get(city) do
      nil ->
        Logger.error("❌ Unknown city: #{city}")
        {:error, :unknown_city}

      city_config ->
        do_perform(job, movie_slug, source_id, city, city_config)
    end
  end

  defp do_perform(job, movie_slug, source_id, city, city_config) do
    Logger.info("""
    🎬 Processing movie: #{movie_slug}
    City: #{city_config.name}
    """)

    # External ID for tracking - includes city
    external_id = "repertuary_#{city}_movie_#{movie_slug}"

    # Fetch movie detail page using city-specific URL
    url = Config.movie_detail_url(movie_slug, city)
    headers = [{"User-Agent", Config.user_agent()}]

    result =
      case HTTPoison.get(url, headers, timeout: Config.timeout()) do
        {:ok, %{status_code: 200, body: html}} ->
          process_movie_html(html, movie_slug, source_id, city, job)

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

  # Process movie HTML and match to TMDB
  defp process_movie_html(html, movie_slug, _source_id, city, job) do
    # Extract movie metadata
    movie_data = MovieExtractor.extract(html)

    Logger.debug(
      "📋 Extracted movie data: #{movie_data.polish_title || movie_data.original_title}"
    )

    # Match to TMDB
    case TmdbMatcher.match_movie(movie_data) do
      {:ok, tmdb_id, confidence, provider} when confidence >= 0.60 ->
        # High confidence match (≥70%) or Now Playing fallback match (60-70%) - auto-accept
        match_type = if confidence >= 0.70, do: "standard", else: "now_playing_fallback"

        # Pass provider info to find_or_create_movie for tracking
        case TmdbMatcher.find_or_create_movie(tmdb_id, matched_by_provider: provider) do
          {:ok, movie} ->
            Logger.info(
              "✅ Auto-matched (#{match_type}) via #{provider}: #{movie.title} (#{trunc(confidence * 100)}% confidence)"
            )

            # Store Repertuary.pl slug and provider in movie metadata for later lookups
            # Using generic key since slugs are consistent across all cities
            store_repertuary_slug(movie, movie_slug, provider)

            # Return standardized metadata structure for job tracking (Phase 3.1)
            {:ok,
             %{
               "job_role" => "detail_fetcher",
               "pipeline_id" => "repertuary_#{city}_#{Date.utc_today()}",
               "parent_job_id" => Map.get(job.meta, "parent_job_id"),
               "entity_id" => movie_slug,
               "entity_type" => "movie",
               "city" => city,
               "items_processed" => 1,
               "status" => "matched",
               "confidence" => confidence,
               "movie_id" => movie.id,
               "tmdb_id" => tmdb_id,
               "match_type" => match_type,
               "matched_by_provider" => provider
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
           movie_slug: movie_slug,
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
           movie_slug: movie_slug,
           polish_title: movie_data.polish_title,
           original_title: movie_data.original_title,
           confidence_range: "<50%"
         }}

      {:error, :missing_title} ->
        Logger.error("❌ TMDB matching failed - missing title for movie: #{movie_slug}")
        {:error, %{reason: :missing_title, movie_slug: movie_slug}}

      {:error, :no_results} ->
        # Return ERROR so Oban marks as failed and visible in dashboard
        Logger.error(
          "❌ TMDB matching failed - no results for: #{movie_data.polish_title || movie_data.original_title}"
        )

        {:error,
         %{
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

  # Store Repertuary.pl slug and matched_by_provider in movie metadata for later database lookups
  # Using generic "repertuary_slug" key since movie slugs are consistent across all cities
  defp store_repertuary_slug(movie, movie_slug, provider) do
    # First, remove this slug from any OTHER movies that have it
    # This handles cases where:
    # - TMDB matching improved and we found the correct movie
    # - Repertuary.pl reassigned the slug to a different movie
    remove_slug_from_other_movies(movie.id, movie_slug)

    # Add repertuary_slug and optionally provider to movie metadata
    current_metadata = movie.metadata || %{}

    updated_metadata =
      current_metadata
      |> Map.put("repertuary_slug", movie_slug)
      |> maybe_put_provider(provider)

    case EventasaurusDiscovery.Movies.MovieStore.update_movie(movie, %{metadata: updated_metadata}) do
      {:ok, _updated_movie} ->
        Logger.debug(
          "💾 Stored Repertuary slug in movie metadata: #{movie_slug} -> #{movie.id} (provider: #{provider || "unknown"})"
        )

        :ok

      {:error, changeset} ->
        Logger.error(
          "❌ Failed to store Repertuary slug in metadata: #{inspect(changeset.errors)}"
        )

        :error
    end
  end

  # Remove repertuary_slug from other movies that have it
  # This prevents duplicates when a slug is reassigned or matching improves
  defp remove_slug_from_other_movies(current_movie_id, movie_slug) do
    import Ecto.Query

    # Find other movies with this slug (not the current movie)
    query =
      from(m in EventasaurusDiscovery.Movies.Movie,
        where: fragment("?->>'repertuary_slug' = ?", m.metadata, ^movie_slug),
        where: m.id != ^current_movie_id
      )

    other_movies = EventasaurusApp.Repo.all(query)

    Enum.each(other_movies, fn old_movie ->
      # Remove the slug from the old movie's metadata
      updated_metadata =
        (old_movie.metadata || %{})
        |> Map.delete("repertuary_slug")

      case EventasaurusDiscovery.Movies.MovieStore.update_movie(old_movie, %{metadata: updated_metadata}) do
        {:ok, _} ->
          Logger.info(
            "🔄 Removed stale repertuary_slug '#{movie_slug}' from movie #{old_movie.id} (#{old_movie.title})"
          )

        {:error, _} ->
          Logger.warning(
            "⚠️ Failed to remove stale repertuary_slug from movie #{old_movie.id}"
          )
      end
    end)
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
