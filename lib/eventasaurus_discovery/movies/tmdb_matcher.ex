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

  ## Options

  - `:matched_by_provider` - Provider that matched this movie (e.g., "tmdb", "omdb", "imdb", "now_playing")
  - `:imdb_id` - IMDB ID if available from the provider (e.g., "tt0172495")

  These are stored in dedicated columns for efficient querying and analytics.
  """
  def find_or_create_movie(tmdb_id, opts \\ []) do
    # Extract provider tracking info from opts
    provider_attrs = build_provider_attrs(opts)

    case MovieStore.find_or_create_by_tmdb_id(tmdb_id, provider_attrs) do
      {:ok, movie} ->
        # If movie already existed but doesn't have provider info, update it
        maybe_update_provider_info(movie, provider_attrs)

      {:error, _} ->
        # If movie doesn't exist, fetch from TMDB and create with provider info
        create_from_tmdb(tmdb_id, provider_attrs)
    end
  end

  # Build provider attributes map from options
  defp build_provider_attrs(opts) do
    attrs = %{}

    attrs =
      if provider = Keyword.get(opts, :matched_by_provider) do
        Map.put(attrs, :matched_by_provider, provider)
      else
        attrs
      end

    if imdb_id = Keyword.get(opts, :imdb_id) do
      Map.put(attrs, :imdb_id, imdb_id)
    else
      attrs
    end
  end

  # Update existing movie with provider info if it's missing
  defp maybe_update_provider_info(movie, provider_attrs) when map_size(provider_attrs) == 0 do
    {:ok, movie}
  end

  defp maybe_update_provider_info(movie, provider_attrs) do
    # Only update if the movie doesn't already have this info
    updates =
      Enum.reduce(provider_attrs, %{}, fn {key, value}, acc ->
        current_value = Map.get(movie, key)

        if is_nil(current_value) or current_value == "" do
          Map.put(acc, key, value)
        else
          acc
        end
      end)

    if map_size(updates) > 0 do
      # Add matched_at if we're setting matched_by_provider
      updates =
        if Map.has_key?(updates, :matched_by_provider) and is_nil(movie.matched_at) do
          Map.put(updates, :matched_at, DateTime.utc_now())
        else
          updates
        end

      case MovieStore.update_movie(movie, updates) do
        {:ok, updated_movie} -> {:ok, updated_movie}
        {:error, _} -> {:ok, movie}
      end
    else
      {:ok, movie}
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

  # Create movie from TMDB data with provider tracking
  defp create_from_tmdb(tmdb_id, provider_attrs) do
    with {:ok, details} <- TmdbService.get_movie_details(tmdb_id) do
      # Extract IMDB ID from TMDB details if available
      imdb_id = details[:imdb_id] || details["imdb_id"]

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

      # Add provider tracking attrs
      attrs =
        attrs
        |> maybe_add_imdb_id(imdb_id, provider_attrs)
        |> maybe_add_provider(provider_attrs)
        |> maybe_add_matched_at(provider_attrs)

      MovieStore.create_movie(attrs)
    end
  end

  # Add IMDB ID - prefer from provider_attrs, fallback to TMDB details
  defp maybe_add_imdb_id(attrs, tmdb_imdb_id, provider_attrs) do
    imdb_id = Map.get(provider_attrs, :imdb_id) || tmdb_imdb_id

    if imdb_id && imdb_id != "" do
      Map.put(attrs, :imdb_id, imdb_id)
    else
      attrs
    end
  end

  # Add matched_by_provider from provider_attrs
  defp maybe_add_provider(attrs, provider_attrs) do
    if provider = Map.get(provider_attrs, :matched_by_provider) do
      Map.put(attrs, :matched_by_provider, provider)
    else
      attrs
    end
  end

  # Add matched_at timestamp if provider is set
  defp maybe_add_matched_at(attrs, _provider_attrs) do
    if Map.has_key?(attrs, :matched_by_provider) do
      Map.put(attrs, :matched_at, DateTime.utc_now())
    else
      attrs
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
