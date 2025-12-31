defmodule EventasaurusDiscovery.Movies.Providers.TmdbProvider do
  @moduledoc """
  TMDB (The Movie Database) provider implementation.

  This is the primary provider for movie lookups, offering comprehensive
  movie data with multiple search strategies:

  1. Exact title match
  2. Language-specific search (Polish, English, etc.)
  3. Alternative titles lookup
  4. Upcoming/Now Playing search
  5. Fuzzy matching with confidence scoring

  ## Priority

  Priority: 10 (primary provider)

  ## Supported Languages

  Supports all languages available in TMDB (200+), but optimized for:
  - English (en)
  - Polish (pl)
  """

  @behaviour EventasaurusDiscovery.Movies.Provider

  require Logger

  alias EventasaurusWeb.Services.TmdbService

  # Provider configuration
  # NOTE: Must be a string for Ecto to cast to :string type in Movie schema
  @provider_name "tmdb"
  @provider_priority 10
  @supported_languages ~w(en pl de fr es it ja zh ko ru pt)

  @impl true
  def name, do: @provider_name

  @impl true
  def priority, do: @provider_priority

  @impl true
  def supports_language?(lang) when is_binary(lang) do
    # TMDB supports most languages, but we have optimized support for these
    lang in @supported_languages
  end

  @impl true
  def search(query, opts \\ []) do
    language = Keyword.get(opts, :language)
    year = Keyword.get(opts, :year) || Map.get(query, :year)

    # Build list of titles to search
    titles = build_search_titles(query)

    # Try each title until we find results
    result =
      Enum.find_value(titles, fn {title, search_lang} ->
        actual_lang = search_lang || language

        case search_single_title(title, year, actual_lang) do
          {:ok, [_ | _] = results} ->
            # Add provider metadata and calculate confidence
            enriched =
              Enum.map(results, fn result ->
                result
                |> Map.put(:provider, @provider_name)
                |> Map.put(:confidence, calculate_confidence(result, query))
              end)

            {:ok, enriched}

          _ ->
            nil
        end
      end)

    result || {:ok, []}
  end

  @impl true
  def get_details(tmdb_id) when is_integer(tmdb_id) do
    case TmdbService.get_movie_details(tmdb_id) do
      {:ok, details} ->
        {:ok, format_details(details)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_details(tmdb_id) when is_binary(tmdb_id) do
    case Integer.parse(tmdb_id) do
      {id, ""} -> get_details(id)
      _ -> {:error, :invalid_id}
    end
  end

  @impl true
  def confidence_score(result, query) do
    calculate_confidence(result, query)
  end

  # Build list of titles to search with their preferred languages
  defp build_search_titles(query) do
    titles = []

    # Original title (English) - search without language param
    titles =
      if query[:original_title] && query[:original_title] != "" do
        [{query[:original_title], nil} | titles]
      else
        titles
      end

    # Polish title - search with Polish language
    titles =
      if query[:polish_title] && query[:polish_title] != "" do
        [{query[:polish_title], "pl"} | titles]
      else
        titles
      end

    # Generic title field - try both ways
    titles =
      if query[:title] && query[:title] != "" do
        [{query[:title], nil}, {query[:title], "pl"} | titles]
      else
        titles
      end

    # Normalize titles for better matching
    normalized =
      titles
      |> Enum.flat_map(fn {title, lang} ->
        normalized_title = normalize_title(title)

        if normalized_title != title do
          [{title, lang}, {normalized_title, lang}]
        else
          [{title, lang}]
        end
      end)

    Enum.reverse(normalized)
  end

  # Search for a single title
  defp search_single_title(title, year, language) do
    case TmdbService.search_multi(title, 1, language) do
      {:ok, [_ | _] = results} ->
        # Filter to movies only and optionally by year
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

  # Filter results by year if provided (±1 year tolerance)
  defp maybe_filter_by_year(movies, nil), do: movies

  defp maybe_filter_by_year(movies, year) when is_integer(year) do
    filtered =
      Enum.filter(movies, fn movie ->
        case extract_year(movie[:release_date]) do
          nil -> true
          movie_year -> abs(movie_year - year) <= 1
        end
      end)

    # Return unfiltered if filtering removes all results
    if filtered == [], do: movies, else: filtered
  end

  # Extract year from release date string
  defp extract_year(nil), do: nil

  defp extract_year(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date.year
      _ -> nil
    end
  end

  # Normalize title for search
  defp normalize_title(title) when is_binary(title) do
    title
    |> remove_format_suffixes()
    |> remove_screening_suffixes()
    |> String.trim()
  end

  # Remove format suffixes (3D, IMAX, etc.)
  defp remove_format_suffixes(title) do
    ~w(3D IMAX 4K Dolby\ Atmos Extended Director's\ Cut Unrated Remastered)
    |> Enum.reduce(title, fn suffix, acc ->
      String.replace(acc, ~r/\s+#{Regex.escape(suffix)}$/i, "")
    end)
  end

  # Remove Polish screening type suffixes (NAP, KNT, etc.)
  defp remove_screening_suffixes(title) do
    title
    |> String.replace(~r/\s+[-–]\s*(NAP|KNT|DKF|PKF)\s*$/i, "")
    |> String.replace(~r/\s+(NAP|KNT|DKF|PKF)\s*$/i, "")
  end

  # Format details from TmdbService response
  # Note: TmdbService.get_movie_details returns :tmdb_id, not :id
  defp format_details(details) do
    %{
      tmdb_id: details[:tmdb_id],
      title: details[:title],
      overview: details[:overview],
      release_date: details[:release_date],
      runtime: details[:runtime],
      poster_path: details[:poster_path],
      backdrop_path: details[:backdrop_path],
      genres: details[:genres],
      vote_average: details[:vote_average],
      vote_count: details[:vote_count],
      production_countries: details[:production_countries],
      original_language: details[:original_language],
      provider: @provider_name
    }
  end

  # Calculate confidence score (0.0 - 1.0)
  defp calculate_confidence(result, query) do
    # Title similarity (40%)
    title_score = calculate_title_score(result, query) * 0.40

    # Year matching (30%)
    year_score = calculate_year_score(result, query) * 0.30

    # Popularity boost (15%) - more popular movies are more likely correct
    popularity_score = calculate_popularity_score(result) * 0.15

    # Language match (15%)
    language_score = calculate_language_score(result, query) * 0.15

    title_score + year_score + popularity_score + language_score
  end

  # Calculate title similarity score
  defp calculate_title_score(result, query) do
    query_titles =
      [query[:title], query[:original_title], query[:polish_title]]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.map(&String.downcase/1)

    result_titles =
      [result[:title], result[:original_title]]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.map(&String.downcase/1)

    if Enum.empty?(query_titles) or Enum.empty?(result_titles) do
      0.0
    else
      # Find best match between any query title and result title
      for qt <- query_titles, rt <- result_titles, reduce: 0.0 do
        acc -> max(acc, String.jaro_distance(qt, rt))
      end
    end
  end

  # Calculate year match score
  defp calculate_year_score(_result, %{year: nil}), do: 0.5
  defp calculate_year_score(%{release_date: nil}, _query), do: 0.5

  defp calculate_year_score(result, query) do
    query_year = query[:year]
    result_year = extract_year(result[:release_date])

    cond do
      is_nil(query_year) or is_nil(result_year) -> 0.5
      query_year == result_year -> 1.0
      abs(query_year - result_year) == 1 -> 0.8
      abs(query_year - result_year) == 2 -> 0.5
      true -> 0.0
    end
  end

  # Calculate popularity score (normalized)
  defp calculate_popularity_score(result) do
    popularity = result[:popularity] || 0

    cond do
      popularity >= 100 -> 1.0
      popularity >= 50 -> 0.8
      popularity >= 20 -> 0.6
      popularity >= 5 -> 0.4
      true -> 0.2
    end
  end

  # Calculate language match score
  defp calculate_language_score(result, query) do
    result_lang = result[:original_language]
    query_country = query[:country]

    cond do
      is_nil(result_lang) -> 0.5
      query_country && language_matches_country?(result_lang, query_country) -> 1.0
      result_lang == "en" -> 0.7
      true -> 0.5
    end
  end

  # Check if language matches expected country
  defp language_matches_country?(lang, country) when is_binary(country) do
    country_lower = String.downcase(country)

    case lang do
      "pl" -> country_lower =~ ~r/poland|polish|polska/
      "en" -> country_lower =~ ~r/usa|uk|united|america|britain|english/
      "fr" -> country_lower =~ ~r/france|french/
      "de" -> country_lower =~ ~r/germany|german/
      "es" -> country_lower =~ ~r/spain|spanish/
      "it" -> country_lower =~ ~r/italy|italian/
      "ja" -> country_lower =~ ~r/japan|japanese/
      "ko" -> country_lower =~ ~r/korea|korean/
      _ -> false
    end
  end
end
