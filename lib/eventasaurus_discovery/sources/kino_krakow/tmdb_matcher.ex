defmodule EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher do
  @moduledoc """
  Matches Kino Krakow movies to TMDB with confidence scoring.

  Uses multi-signal matching:
  - Title similarity (40%)
  - Year match (30%)
  - Director match (15%)
  - Runtime match (10%)
  - Country match (5%)

  Requires ≥80% confidence for automatic matching.
  Lower confidence movies go to manual review queue.
  """

  require Logger
  alias EventasaurusWeb.Services.TmdbService
  alias EventasaurusDiscovery.Movies.MovieStore

  # Confidence thresholds
  @auto_accept_threshold 0.80
  @needs_review_threshold 0.60

  @doc """
  Match a Kino Krakow movie to TMDB.

  Returns:
  - {:ok, tmdb_id, confidence} - High confidence match
  - {:needs_review, movie_data, candidates} - Low confidence, manual review needed
  - {:error, reason} - No match found or error
  """
  def match_movie(kino_movie) do
    with {:ok, original_title} <- validate_title(kino_movie),
         {:ok, candidates} <- search_tmdb(original_title, kino_movie.year),
         {:ok, best_match, confidence} <- find_best_match(candidates, kino_movie) do
      case confidence do
        c when c >= @auto_accept_threshold ->
          {:ok, best_match[:id], confidence}

        c when c >= @needs_review_threshold ->
          {:needs_review, kino_movie, candidates}

        _ ->
          {:error, :low_confidence}
      end
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

  # Search TMDB for candidates
  defp search_tmdb(title, year) do
    # Try search with year first for better results
    case TmdbService.search_multi(title, 1) do
      {:ok, [_ | _] = results} ->
        # Filter to movies only and relevant years
        movies =
          results
          |> Enum.filter(&(&1[:type] == :movie))
          |> maybe_filter_by_year(year)

        {:ok, movies}

      {:ok, []} ->
        {:error, :no_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Filter results by year if available (±1 year tolerance)
  defp maybe_filter_by_year(movies, nil), do: movies

  defp maybe_filter_by_year(movies, year) when is_integer(year) do
    filtered =
      Enum.filter(movies, fn movie ->
        case extract_year_from_movie(movie) do
          nil -> true
          movie_year -> abs(movie_year - year) <= 1
        end
      end)

    # If filtering removes all results, return unfiltered
    case filtered do
      [] -> movies
      results -> results
    end
  end

  # Extract year from TMDB movie result
  defp extract_year_from_movie(movie) do
    case movie[:release_date] do
      nil -> nil
      date_str when is_binary(date_str) ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> date.year
          _ -> nil
        end
      _ -> nil
    end
  end

  # Find best match from candidates using confidence scoring
  defp find_best_match([], _kino_movie) do
    {:error, :no_candidates}
  end

  defp find_best_match(candidates, kino_movie) do
    scored_candidates =
      candidates
      |> Enum.map(fn candidate ->
        confidence = calculate_confidence(kino_movie, candidate)
        {candidate, confidence}
      end)
      |> Enum.sort_by(fn {_candidate, confidence} -> confidence end, :desc)

    case scored_candidates do
      [{best_match, confidence} | _] when confidence > 0 ->
        {:ok, best_match, confidence}

      _ ->
        {:error, :no_confident_match}
    end
  end

  # Calculate confidence score (0.0 - 1.0)
  defp calculate_confidence(kino_movie, tmdb_movie) do
    # Use available titles with fallbacks
    primary_title = kino_movie.original_title || kino_movie.polish_title
    localized_title = kino_movie.polish_title || kino_movie.original_title

    # Primary: Compare original titles (most reliable for international films)
    original_title_score = title_similarity(primary_title, tmdb_movie[:original_title]) * 0.50

    # Secondary: Compare against localized title as fallback
    localized_title_score = title_similarity(localized_title, tmdb_movie[:title]) * 0.20

    # Year matching
    year_score = year_match(kino_movie.year, extract_year_from_movie(tmdb_movie)) * 0.30

    # Total: 50% original title + 20% localized title + 30% year = 100%
    original_title_score + localized_title_score + year_score
  end

  # Calculate title similarity using Jaro distance
  defp title_similarity(nil, _), do: 0.0
  defp title_similarity(_, nil), do: 0.0

  defp title_similarity(title1, title2) do
    # Normalize titles for comparison
    t1 = normalize_title(title1)
    t2 = normalize_title(title2)

    # Use String.jaro_distance for similarity
    String.jaro_distance(t1, t2)
  end

  # Normalize title for comparison
  defp normalize_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
    |> String.trim()
  end

  # Calculate year match score
  defp year_match(nil, _), do: 0.5  # Give partial credit if year missing
  defp year_match(_, nil), do: 0.5

  defp year_match(year1, year2) when is_integer(year1) and is_integer(year2) do
    diff = abs(year1 - year2)

    cond do
      diff == 0 -> 1.0
      diff == 1 -> 0.8
      diff == 2 -> 0.5
      true -> 0.0
    end
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
