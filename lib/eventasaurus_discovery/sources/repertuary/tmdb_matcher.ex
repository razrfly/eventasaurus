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
  import Ecto.Query
  alias EventasaurusWeb.Services.TmdbService
  alias EventasaurusDiscovery.Movies.MovieStore
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusApp.Repo

  # Confidence thresholds
  # Lowered from 0.80 to 0.70 to capture more valid matches (60-79% range had many good matches)
  @auto_accept_threshold 0.70
  # Lowered from 0.60 to 0.50 to reduce manual review queue
  @needs_review_threshold 0.50
  # "Now Playing" fallback uses more lenient threshold since it's a curated list
  @now_playing_threshold 0.60

  @doc """
  Match a Kino Krakow movie to TMDB using multi-strategy search.

  Returns:
  - {:ok, tmdb_id, confidence} - High confidence match
  - {:needs_review, movie_data, candidates} - Low confidence, manual review needed
  - {:error, reason} - No match found or error
  """
  def match_movie(kino_movie) do
    with {:ok, _original_title} <- validate_title(kino_movie),
         {:ok, candidates} <- search_with_fallbacks(kino_movie),
         {:ok, best_match, confidence} <- find_best_match(candidates, kino_movie) do
      case confidence do
        c when c >= @auto_accept_threshold ->
          {:ok, best_match[:id], confidence}

        c when c >= @needs_review_threshold ->
          # Try "Now Playing" fallback before manual review
          try_now_playing_fallback(kino_movie, {:needs_review, kino_movie, candidates})

        _ ->
          # Try "Now Playing" fallback before rejecting
          try_now_playing_fallback(kino_movie, {:error, :low_confidence})
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

  # Multi-strategy search with fallbacks for better match rate
  defp search_with_fallbacks(kino_movie) do
    primary_title = kino_movie.original_title || kino_movie.polish_title
    polish_title = kino_movie.polish_title
    year = kino_movie.year

    strategies = [
      # Strategy 1: Original title + year (most accurate)
      {fn -> search_tmdb(primary_title, year, nil) end, "original_title+year"},

      # Strategy 2: Normalized title (remove 3D/IMAX/etc) + year
      {fn -> search_tmdb(normalize_title_for_search(primary_title), year, nil) end,
       "normalized+year"},

      # Strategy 3: Main title only (handle subtitles like "Film: Subtitle")
      {fn -> search_tmdb(extract_main_title(primary_title), year, nil) end, "main_title+year"},

      # Strategy 4: Original title without year (broader search)
      {fn -> search_tmdb(primary_title, nil, nil) end, "original_title"},

      # Strategy 5: Polish title + year (for Polish-only films) - USE POLISH LANGUAGE
      {fn -> polish_title && search_tmdb(polish_title, year, "pl-PL") end, "polish_title+year"},

      # Strategy 6: Normalized Polish title + year (handles collections, prefixes) - USE POLISH LANGUAGE
      {fn -> polish_title && search_tmdb(normalize_polish_title(polish_title), year, "pl-PL") end,
       "polish_normalized+year"},

      # Strategy 7: Normalized Polish title without year (broader search) - USE POLISH LANGUAGE
      {fn -> polish_title && search_tmdb(normalize_polish_title(polish_title), nil, "pl-PL") end,
       "polish_normalized"},

      # Strategy 8: Normalized without year (last resort)
      {fn -> search_tmdb(normalize_title_for_search(primary_title), nil, nil) end, "normalized"},

      # Strategy 9: Movie-specific search endpoint (better ranking) - Try with Polish if available
      {fn -> polish_title && search_movie_only(polish_title, year, "pl-PL") end,
       "movie_endpoint+polish"},

      # Strategy 10: Movie-specific search endpoint (original title fallback)
      {fn -> search_movie_only(primary_title, year, nil) end, "movie_endpoint+year"},

      # Strategy 11: Discover with metadata filters (runtime, language)
      {fn -> discover_by_metadata(kino_movie) end, "discover_metadata"}
    ]

    # Try each strategy until we find results
    result =
      Enum.find_value(strategies, fn {strategy_fn, strategy_name} ->
        case strategy_fn.() do
          {:ok, [_ | _] = results} ->
            Logger.info("✅ TMDB match found using strategy: #{strategy_name}")
            {:ok, results}

          _ ->
            nil
        end
      end)

    result || {:error, :no_results}
  end

  # Search TMDB for candidates (uses /search/multi endpoint)
  defp search_tmdb(nil, _year, _language), do: {:ok, []}

  defp search_tmdb(title, year, language) when is_binary(title) do
    # Try search with language parameter for better Polish title matching
    case TmdbService.search_multi(title, 1, language) do
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

  # Search using movie-specific endpoint for better ranking
  defp search_movie_only(nil, _year, _language), do: {:ok, []}

  defp search_movie_only(title, year, language) when is_binary(title) do
    api_key = System.get_env("TMDB_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      # Build query params
      params = %{
        api_key: api_key,
        query: title,
        page: 1,
        include_adult: false
      }

      # Add year if available
      params = if year, do: Map.put(params, :year, year), else: params

      # Add language if available (for Polish searches)
      params = if language, do: Map.put(params, :language, language), else: params

      # Build URL
      query_string = URI.encode_query(params)
      url = "https://api.themoviedb.org/3/search/movie?#{query_string}"

      case HTTPoison.get(url, [{"Accept", "application/json"}]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"results" => results}} ->
              movies =
                results
                |> Enum.map(&format_movie_result/1)
                |> maybe_filter_by_year(year)

              {:ok, movies}

            {:error, _} ->
              {:error, :decode_error}
          end

        {:ok, %HTTPoison.Response{status_code: _}} ->
          {:error, :api_error}

        {:error, _} ->
          {:error, :network_error}
      end
    end
  end

  # Discover movies using metadata filters (runtime, language, year)
  defp discover_by_metadata(kino_movie) do
    api_key = System.get_env("TMDB_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      # Build query params with metadata filters
      params = %{
        api_key: api_key,
        page: 1,
        include_adult: false,
        sort_by: "popularity.desc"
      }

      # Add year filter if available
      params =
        if kino_movie.year do
          params
          |> Map.put(:primary_release_year, kino_movie.year)
          |> Map.put(:"primary_release_date.gte", "#{kino_movie.year}-01-01")
          |> Map.put(:"primary_release_date.lte", "#{kino_movie.year}-12-31")
        else
          params
        end

      # Add runtime filter if available (±10 minutes tolerance)
      params =
        if kino_movie.runtime do
          params
          |> Map.put(:"with_runtime.gte", max(0, kino_movie.runtime - 10))
          |> Map.put(:"with_runtime.lte", kino_movie.runtime + 10)
        else
          params
        end

      # Add language filter if we can detect it from country
      params =
        case detect_language_from_country(kino_movie.country) do
          nil -> params
          lang -> Map.put(params, :with_original_language, lang)
        end

      # Build URL
      query_string = URI.encode_query(params)
      url = "https://api.themoviedb.org/3/discover/movie?#{query_string}"

      case HTTPoison.get(url, [{"Accept", "application/json"}]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"results" => results}} ->
              movies = Enum.map(results, &format_movie_result/1)
              {:ok, movies}

            {:error, _} ->
              {:error, :decode_error}
          end

        {:ok, %HTTPoison.Response{status_code: _}} ->
          {:error, :api_error}

        {:error, _} ->
          {:error, :network_error}
      end
    end
  end

  # Format movie result from /search/movie or /discover/movie endpoints
  defp format_movie_result(movie) do
    %{
      type: :movie,
      id: movie["id"],
      title: movie["title"],
      original_title: movie["original_title"],
      original_language: movie["original_language"],
      overview: movie["overview"],
      poster_path: movie["poster_path"],
      release_date: movie["release_date"],
      vote_average: movie["vote_average"],
      popularity: movie["popularity"]
    }
  end

  # Detect TMDB language code from country name
  defp detect_language_from_country(nil), do: nil

  defp detect_language_from_country(country) when is_binary(country) do
    country_lower = String.downcase(country)

    cond do
      country_lower =~ ~r/poland|polish/ -> "pl"
      country_lower =~ ~r/france|french/ -> "fr"
      country_lower =~ ~r/spain|spanish/ -> "es"
      country_lower =~ ~r/germany|german/ -> "de"
      country_lower =~ ~r/italy|italian/ -> "it"
      country_lower =~ ~r/japan|japanese/ -> "ja"
      country_lower =~ ~r/china|chinese/ -> "zh"
      country_lower =~ ~r/korea|korean/ -> "ko"
      country_lower =~ ~r/russia|russian/ -> "ru"
      true -> nil
    end
  end

  # Normalize title for better TMDB matching
  defp normalize_title_for_search(nil), do: nil

  defp normalize_title_for_search(title) do
    title
    |> remove_common_suffixes()
    |> remove_redundant_words()
    |> String.trim()
  end

  # Normalize Polish-specific title patterns for better matching
  # Handles common Polish title formats that don't exist in TMDB
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

  # Remove common movie suffixes (3D, IMAX, etc.)
  defp remove_common_suffixes(title) do
    suffixes = ~w(3D IMAX 4K Extended Director's\ Cut Unrated Special\ Edition Remastered)

    Enum.reduce(suffixes, title, fn suffix, acc ->
      String.replace(acc, ~r/\s+#{suffix}$/i, "")
    end)
  end

  # Remove redundant duplicate words (e.g., "Chopin Chopin" → "Chopin")
  defp remove_redundant_words(title) do
    words = String.split(title)

    case words do
      # Same word twice
      [word, word] -> word
      _ -> title
    end
  end

  # Extract main title from subtitle format (e.g., "Film: Subtitle" → "Film")
  defp extract_main_title(nil), do: nil

  defp extract_main_title(title) do
    case String.split(title, ~r/[:\-–—]/, parts: 2) do
      [main, _subtitle] -> String.trim(main)
      _ -> title
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
      nil ->
        nil

      date_str when is_binary(date_str) ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> date.year
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Find best match from candidates using confidence scoring
  defp find_best_match([], _kino_movie) do
    {:error, :no_candidates}
  end

  defp find_best_match(candidates, kino_movie) do
    # Enrich top candidates with runtime data from movie details
    enriched_candidates = enrich_top_candidates(candidates)

    scored_candidates =
      enriched_candidates
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

  # Enrich top candidates with runtime from movie details (for better confidence scoring)
  defp enrich_top_candidates(candidates) do
    # Only enrich top 3 candidates to avoid excessive API calls
    candidates
    |> Enum.take(3)
    |> Enum.map(fn candidate ->
      case TmdbService.get_cached_movie_details(candidate[:id]) do
        {:ok, details} ->
          # Add runtime to candidate
          Map.put(candidate, :runtime, details[:runtime])

        {:error, _} ->
          # Keep candidate as-is if enrichment fails
          candidate
      end
    end)
    # Add remaining candidates without enrichment
    |> Kernel.++(Enum.drop(candidates, 3))
  end

  # Calculate confidence score (0.0 - 1.0) using multi-signal matching
  defp calculate_confidence(kino_movie, tmdb_movie) do
    # Use available titles with fallbacks
    primary_title = kino_movie.original_title || kino_movie.polish_title
    localized_title = kino_movie.polish_title || kino_movie.original_title

    # Title similarity (40% total)
    # Primary: Compare original titles (most reliable for international films)
    original_title_score = title_similarity(primary_title, tmdb_movie[:original_title]) * 0.25
    # Secondary: Compare against localized title as fallback
    localized_title_score = title_similarity(localized_title, tmdb_movie[:title]) * 0.15

    # Year matching (25%)
    year_score = year_match(kino_movie.year, extract_year_from_movie(tmdb_movie)) * 0.25

    # Runtime matching (15%) - NEW
    runtime_score = runtime_match(kino_movie.runtime, tmdb_movie[:runtime]) * 0.15

    # Director matching (10%) - NEW (requires fetching full details)
    director_score = director_match(kino_movie.director, tmdb_movie[:id]) * 0.10

    # Country/Language matching (10%) - NEW
    country_score = country_match(kino_movie.country, tmdb_movie[:original_language]) * 0.10

    # Total: 40% title + 25% year + 15% runtime + 10% director + 10% country = 100%
    original_title_score + localized_title_score + year_score + runtime_score + director_score +
      country_score
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
  # Improved tolerance for upcoming releases and release date variations
  # Give partial credit if year missing
  defp year_match(nil, _), do: 0.5
  defp year_match(_, nil), do: 0.5

  defp year_match(year1, year2) when is_integer(year1) and is_integer(year2) do
    diff = abs(year1 - year2)

    cond do
      # Perfect match
      diff == 0 -> 1.0
      # ±1 year (regional release differences) - increased from 0.8
      diff == 1 -> 0.9
      # ±2 years (festival vs theatrical) - increased from 0.5
      diff == 2 -> 0.7
      # ±3 years (very upcoming releases or re-releases) - new
      diff == 3 -> 0.4
      # Too far apart
      true -> 0.0
    end
  end

  # Calculate runtime match score (±5 minutes tolerance)
  # Give partial credit if runtime missing
  defp runtime_match(nil, _), do: 0.5
  defp runtime_match(_, nil), do: 0.5

  defp runtime_match(runtime1, runtime2) when is_integer(runtime1) and is_integer(runtime2) do
    diff = abs(runtime1 - runtime2)

    cond do
      # Within 5 minutes = perfect match
      diff <= 5 -> 1.0
      # Within 10 minutes = good match
      diff <= 10 -> 0.8
      # Within 15 minutes = partial match
      diff <= 15 -> 0.5
      # Too different
      true -> 0.0
    end
  end

  # Calculate director match score
  # Give partial credit if director missing
  defp director_match(nil, _tmdb_id), do: 0.5
  defp director_match(_director, nil), do: 0.5

  defp director_match(kino_director, tmdb_id) when is_binary(kino_director) do
    # Fetch movie details to get director info (cached by TmdbService)
    case TmdbService.get_cached_movie_details(tmdb_id) do
      {:ok, details} ->
        tmdb_director_name = get_in(details, [:director, :name])

        if tmdb_director_name do
          # Normalize and compare director names
          kino_normalized = normalize_title(kino_director)
          tmdb_normalized = normalize_title(tmdb_director_name)

          # Use Jaro distance for name similarity
          similarity = String.jaro_distance(kino_normalized, tmdb_normalized)

          cond do
            # Very similar names
            similarity >= 0.9 -> 1.0
            # Fairly similar
            similarity >= 0.7 -> 0.7
            # Somewhat similar
            similarity >= 0.5 -> 0.4
            # Too different
            true -> 0.0
          end
        else
          # No director in TMDB data
          0.5
        end

      {:error, _} ->
        # Error fetching details, give partial credit
        0.5
    end
  end

  # Calculate country/language match score
  defp country_match(nil, _tmdb_language), do: 0.5
  defp country_match(_country, nil), do: 0.5

  defp country_match(kino_country, tmdb_language)
       when is_binary(kino_country) and is_binary(tmdb_language) do
    # Map country to expected language code
    expected_language = detect_language_from_country(kino_country)

    cond do
      # Unknown country, partial credit
      is_nil(expected_language) -> 0.5
      # Perfect match
      expected_language == tmdb_language -> 1.0
      # Mismatch
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

  # Try matching against "Now Playing" movies as a fallback
  defp try_now_playing_fallback(kino_movie, fallback_result) do
    case match_against_now_playing(kino_movie) do
      {:ok, tmdb_id, confidence} ->
        Logger.info(
          "✨ Matched via Now Playing fallback: #{tmdb_id} (#{trunc(confidence * 100)}%)"
        )

        {:ok, tmdb_id, confidence}

      _ ->
        # No match in Now Playing, return original result
        fallback_result
    end
  end

  # Match against pre-populated "Now Playing" movies in database
  defp match_against_now_playing(kino_movie) do
    polish_title = kino_movie.polish_title || kino_movie.original_title

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
end
