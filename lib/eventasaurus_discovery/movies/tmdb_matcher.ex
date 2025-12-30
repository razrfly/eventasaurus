defmodule EventasaurusDiscovery.Movies.TmdbMatcher do
  @moduledoc """
  Universal TMDB matching service for all movie sources.

  **DEPRECATED**: This module now delegates to `MovieLookupService` for all lookups.
  Consider using `MovieLookupService` directly for new code.

  ## Migration to MovieLookupService

  For new code, prefer using MovieLookupService directly:

      alias EventasaurusDiscovery.Movies.MovieLookupService

      case MovieLookupService.lookup(query) do
        {:ok, tmdb_id, confidence} -> # Match found
        {:needs_review, candidates} -> # Needs review
        {:error, reason} -> # No match
      end

  ## Legacy Support

  This module maintains backward compatibility for existing code that uses:
  - `TmdbMatcher.match_movie/1` - Now delegates to MovieLookupService
  - `TmdbMatcher.find_or_create_movie/1` - Creates/finds movies in database

  The "Now Playing" database fallback is still supported for cases where
  MovieLookupService returns no results.
  """

  require Logger
  import Ecto.Query
  alias EventasaurusWeb.Services.TmdbService
  alias EventasaurusDiscovery.Movies.{MovieStore, Movie, MovieLookupService}
  alias EventasaurusApp.Repo

  # "Now Playing" fallback uses more lenient threshold since it's a curated list
  @now_playing_threshold 0.60

  @doc """
  Match a movie to TMDB using MovieLookupService.

  This function now delegates to MovieLookupService for all lookups,
  which orchestrates TmdbProvider and OmdbProvider with intelligent fallback.

  ## Parameters

  - `movie_data` - A map with movie information:
    - `:original_title` - Original (English) title
    - `:polish_title` - Polish title
    - `:year` - Release year (integer)
    - `:runtime` - Runtime in minutes (integer)
    - `:director` - Director name (string)
    - `:country` - Country of origin (string)

  ## Returns

  - `{:ok, tmdb_id, confidence, provider}` - High confidence match with provider name
  - `{:needs_review, movie_data, candidates}` - Low confidence, manual review needed
  - `{:error, reason}` - No match found or error

  The `provider` field indicates which provider found the match:
  - `"tmdb"` - TMDB (free, primary)
  - `"omdb"` - OMDb (paid, secondary)
  - `"imdb"` - IMDB via Zyte (paid, tertiary)
  - `"now_playing"` - Matched against pre-synced Now Playing database

  Note: This function returns a 4-tuple for backward compatibility.
  For access to extra data like imdb_id, use MovieLookupService.lookup/2 directly.
  """
  def match_movie(movie_data) do
    # Validate we have at least one title
    case validate_title(movie_data) do
      {:ok, _title} ->
        # Delegate to MovieLookupService
        case MovieLookupService.lookup(movie_data) do
          {:ok, tmdb_id, confidence, provider, _extra} ->
            # Return 4-tuple for backward compatibility
            {:ok, tmdb_id, confidence, provider}

          {:needs_review, candidates} ->
            # Convert to legacy format for backward compatibility
            {:needs_review, movie_data, candidates}

          {:error, :no_results} ->
            # Fall back to "Now Playing" database lookup
            try_now_playing_fallback_only(movie_data)

          {:error, :low_confidence} ->
            # Fall back to "Now Playing" database lookup
            try_now_playing_fallback_only(movie_data)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Find or create movie in our database from TMDB ID.
  """
  def find_or_create_movie(tmdb_id) do
    case MovieStore.find_or_create_by_tmdb_id(tmdb_id) do
      {:ok, movie} ->
        {:ok, movie}

      {:error, _} ->
        # If movie doesn't exist, fetch from TMDB and create
        create_from_tmdb(tmdb_id)
    end
  end

  # Validate movie has required title
  defp validate_title(%{original_title: title}) when is_binary(title) and byte_size(title) > 0 do
    {:ok, title}
  end

  defp validate_title(%{polish_title: title}) when is_binary(title) and byte_size(title) > 0 do
    Logger.warning("No original title, using Polish title for search")
    {:ok, title}
  end

  defp validate_title(_) do
    {:error, :missing_title}
  end

  # Try only the "Now Playing" database lookup as final fallback
  # This checks movies we've already synced from TMDB's now_playing endpoint
  defp try_now_playing_fallback_only(movie_data) do
    case match_against_now_playing(movie_data) do
      {:ok, tmdb_id, confidence} ->
        Logger.info(
          "✨ Matched via Now Playing database: #{tmdb_id} (#{trunc(confidence * 100)}%)"
        )

        {:ok, tmdb_id, confidence, "now_playing"}

      _ ->
        {:error, :no_results}
    end
  end

  # Match against pre-populated "Now Playing" movies in database
  defp match_against_now_playing(movie_data) do
    polish_title = movie_data[:polish_title] || movie_data[:original_title]

    if is_nil(polish_title) or polish_title == "" do
      {:error, :no_title}
    else
      # Query movies with "PL" in now_playing_regions (recent releases)
      # Use last 90 days to cover movies that may have left theaters recently
      ninety_days_ago = Date.utc_today() |> Date.add(-90)

      recent_movies =
        from(m in Movie,
          where: fragment("? @> ?", m.metadata, ^%{"now_playing_regions" => ["PL"]}),
          where: m.release_date >= ^ninety_days_ago,
          select: %{
            tmdb_id: m.tmdb_id,
            title: m.title,
            original_title: m.original_title,
            polish_title: fragment("?->'translations'->'pl'->>'title'", m.metadata),
            release_date: m.release_date
          }
        )
        |> Repo.all()

      # Fuzzy match against this small curated set
      matches =
        recent_movies
        |> Enum.map(fn movie ->
          # Try matching against Polish title from metadata
          polish_score =
            if movie.polish_title && movie.polish_title != "" do
              String.jaro_distance(
                normalize_title(polish_title),
                normalize_title(movie.polish_title)
              )
            else
              0.0
            end

          # Also try original title
          original_score =
            String.jaro_distance(
              normalize_title(polish_title),
              normalize_title(movie.original_title || movie.title)
            )

          # Try normalized versions for Polish titles
          normalized_polish_score =
            if movie.polish_title && movie.polish_title != "" do
              String.jaro_distance(
                normalize_polish_title(polish_title),
                normalize_polish_title(movie.polish_title)
              )
            else
              0.0
            end

          best_score = Enum.max([polish_score, original_score, normalized_polish_score])

          {movie.tmdb_id, best_score}
        end)
        |> Enum.filter(fn {_id, score} -> score >= @now_playing_threshold end)
        |> Enum.sort_by(fn {_id, score} -> score end, :desc)

      case matches do
        [{tmdb_id, confidence} | _] -> {:ok, tmdb_id, confidence}
        [] -> {:error, :no_match}
      end
    end
  end

  # Normalize title for comparison
  defp normalize_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
    |> String.trim()
  end

  # Normalize Polish-specific title patterns for better matching
  defp normalize_polish_title(nil), do: nil

  defp normalize_polish_title(title) do
    title
    # Remove "Kolekcja" (Collection) prefix
    |> String.replace(~r/^Kolekcja\s+/i, "")
    # "w kinie:" (in cinema) → space
    |> String.replace(~r/\s+w\s+kinie:\s+/i, " ")
    # Remove Polish exclamations like "górą!"
    |> String.replace(~r/\s+górą!$/i, "")
    # Remove "Niesamowite przygody" (Amazing adventures of)
    |> String.replace(~r/^Niesamowite przygody\s+/i, "")
    # Translate common prefix
    |> String.replace(~r/^Biuro Detektywistyczne\s+/i, "Detective Agency ")
    |> String.trim()
  end

  # Create movie from TMDB data
  defp create_from_tmdb(tmdb_id) do
    with {:ok, details} <- TmdbService.get_movie_details(tmdb_id) do
      attrs = %{
        tmdb_id: tmdb_id,
        title: details[:title],
        original_title: details[:title],
        overview: details[:overview],
        poster_url: build_image_url(details[:poster_path]),
        backdrop_url: build_image_url(details[:backdrop_path]),
        release_date: parse_release_date(details[:release_date]),
        runtime: details[:runtime],
        metadata: %{
          vote_average: details[:vote_average],
          vote_count: details[:vote_count],
          genres: details[:genres],
          production_countries: details[:production_countries]
        }
      }

      MovieStore.create_movie(attrs)
    end
  end

  # Build TMDB image URL
  defp build_image_url(nil), do: nil
  defp build_image_url(path), do: "https://image.tmdb.org/t/p/w500#{path}"

  # Parse release date
  defp parse_release_date(nil), do: nil

  defp parse_release_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
