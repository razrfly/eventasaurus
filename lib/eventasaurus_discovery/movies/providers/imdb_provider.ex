defmodule EventasaurusDiscovery.Movies.Providers.ImdbProvider do
  @moduledoc """
  IMDB provider implementation using Crawlbase web scraping.

  This is a tertiary/fallback provider that searches IMDB via web scraping
  and bridges results to TMDB via IMDB IDs. Particularly useful for:

  - Polish titles that don't match in TMDB/OMDb API searches
  - Classic films where IMDB's AKA (Also Known As) data helps
  - Movies with strong international title variations

  ## How It Works

  1. Search IMDB web with Polish title using Crawlbase JavaScript rendering
  2. Parse search results to extract IMDB IDs
  3. Bridge IMDB ID → TMDB ID via TMDB's `/find` endpoint
  4. Return TMDB-compatible results with confidence scoring

  ## Priority

  Priority: 30 (tertiary/fallback provider - tried after TMDB and OMDb)

  ## Requirements

  - `CRAWLBASE_JS_API_KEY` environment variable must be set
  - Uses JavaScript rendering for IMDB pages
  - More expensive per-request than API-based providers

  ## Supported Languages

  IMDB's AKA data includes Polish titles, making this effective for:
  - Polish (pl) - via AKA data
  - English (en) - native support
  """

  @behaviour EventasaurusDiscovery.Movies.Provider

  require Logger

  alias EventasaurusDiscovery.Movies.ImdbService
  alias EventasaurusWeb.Services.TmdbService

  # Provider configuration
  # NOTE: Must be a string for Ecto to cast to :string type in Movie schema
  @provider_name "imdb"
  @provider_priority 30
  # Supported via AKA data
  @supported_languages ~w(en pl)

  @impl true
  def name, do: @provider_name

  @impl true
  def priority, do: @provider_priority

  @impl true
  def supports_language?(lang) when is_binary(lang) do
    lang in @supported_languages
  end

  @impl true
  def search(query, opts \\ []) do
    # Only proceed if Crawlbase is available
    unless ImdbService.available?() do
      Logger.debug("ImdbProvider: Crawlbase not configured, skipping")
      {:ok, []}
    else
      year = Keyword.get(opts, :year) || Map.get(query, :year)

      # Build list of titles to search
      titles = build_search_titles(query)

      # Try each title until we find results
      result =
        Enum.find_value(titles, fn title ->
          case search_and_bridge(title, year, query) do
            {:ok, [_ | _] = results} -> {:ok, results}
            _ -> nil
          end
        end)

      result || {:ok, []}
    end
  end

  @impl true
  def get_details(imdb_id) when is_binary(imdb_id) do
    # Bridge to TMDB to get full details
    case bridge_to_tmdb(imdb_id) do
      {:ok, tmdb_movie} ->
        {:ok, format_details(tmdb_movie, imdb_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def confidence_score(result, query) do
    calculate_confidence(result, query)
  end

  # Build list of titles to search
  defp build_search_titles(query) do
    [
      query[:polish_title],
      query[:original_title],
      query[:title]
    ]
    |> Enum.filter(&(&1 && &1 != ""))
    |> Enum.uniq()
  end

  # Search IMDB and bridge results to TMDB
  defp search_and_bridge(title, year, query) do
    opts = if year, do: [year: year], else: []

    case ImdbService.search(title, opts) do
      {:ok, [_ | _] = results} ->
        # Bridge top results to TMDB (limit to 3 to avoid excessive API calls)
        bridged =
          results
          |> Enum.take(3)
          |> Enum.flat_map(&bridge_result_to_tmdb(&1, query))

        {:ok, bridged}

      {:ok, []} ->
        {:error, :no_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Bridge a single IMDB result to TMDB
  defp bridge_result_to_tmdb(imdb_result, query) do
    imdb_id = imdb_result.imdb_id

    case bridge_to_tmdb(imdb_id) do
      {:ok, tmdb_movie} ->
        Logger.info("🔗 IMDB→TMDB bridge: #{imdb_id} → TMDB #{tmdb_movie["id"]}")

        [
          %{
            id: tmdb_movie["id"],
            tmdb_id: tmdb_movie["id"],
            imdb_id: imdb_id,
            title: tmdb_movie["title"],
            original_title: tmdb_movie["original_title"],
            release_date: tmdb_movie["release_date"],
            overview: tmdb_movie["overview"],
            poster_path: tmdb_movie["poster_path"],
            vote_average: tmdb_movie["vote_average"],
            popularity: tmdb_movie["popularity"],
            original_language: tmdb_movie["original_language"],
            provider: @provider_name,
            bridge_source: :imdb_web,
            imdb_title: imdb_result.title,
            imdb_year: imdb_result.year,
            confidence: calculate_confidence_for_bridged(tmdb_movie, imdb_result, query)
          }
        ]

      {:error, reason} ->
        Logger.debug("ImdbProvider: Failed to bridge #{imdb_id} to TMDB: #{inspect(reason)}")
        []
    end
  end

  # Bridge IMDB ID to TMDB via the find endpoint
  defp bridge_to_tmdb(imdb_id) do
    case TmdbService.find_by_external_id(imdb_id, "imdb_id") do
      {:ok, %{movie_results: [tmdb_movie | _]}} ->
        {:ok, tmdb_movie}

      {:ok, %{movie_results: []}} ->
        {:error, :not_found_in_tmdb}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Format details from bridged TMDB data
  defp format_details(tmdb_movie, imdb_id) do
    %{
      tmdb_id: tmdb_movie["id"],
      imdb_id: imdb_id,
      title: tmdb_movie["title"],
      original_title: tmdb_movie["original_title"],
      overview: tmdb_movie["overview"],
      release_date: tmdb_movie["release_date"],
      poster_path: tmdb_movie["poster_path"],
      backdrop_path: tmdb_movie["backdrop_path"],
      vote_average: tmdb_movie["vote_average"],
      popularity: tmdb_movie["popularity"],
      original_language: tmdb_movie["original_language"],
      provider: @provider_name,
      bridge_source: :imdb_web
    }
  end

  # Calculate confidence score (0.0 - 1.0)
  defp calculate_confidence(result, query) do
    # Title similarity (45%)
    title_score = calculate_title_score(result, query) * 0.45

    # Year matching (35%)
    year_score = calculate_year_score(result, query) * 0.35

    # Bridge bonus (20%) - if we successfully bridged from IMDB, add confidence
    bridge_score = if result[:bridge_source] == :imdb_web, do: 0.20, else: 0.10

    title_score + year_score + bridge_score
  end

  # Calculate confidence for bridged results (uses both TMDB and IMDB data)
  defp calculate_confidence_for_bridged(tmdb_movie, imdb_result, query) do
    # Title similarity against query
    query_titles =
      [query[:title], query[:original_title], query[:polish_title]]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.map(&String.downcase/1)

    tmdb_titles =
      [tmdb_movie["title"], tmdb_movie["original_title"]]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.map(&String.downcase/1)

    imdb_title =
      if imdb_result.title, do: [String.downcase(imdb_result.title)], else: []

    all_result_titles = tmdb_titles ++ imdb_title

    title_score =
      if Enum.empty?(query_titles) or Enum.empty?(all_result_titles) do
        0.5
      else
        for qt <- query_titles, rt <- all_result_titles, reduce: 0.0 do
          acc -> max(acc, String.jaro_distance(qt, rt))
        end
      end

    # Year matching
    query_year = query[:year]

    tmdb_year =
      case tmdb_movie["release_date"] do
        nil ->
          nil

        "" ->
          nil

        date when is_binary(date) ->
          case String.slice(date, 0..3) do
            "" -> nil
            year_str -> String.to_integer(year_str)
          end
      end

    imdb_year = imdb_result.year

    year_score =
      cond do
        is_nil(query_year) -> 0.5
        query_year == tmdb_year -> 1.0
        query_year == imdb_year -> 1.0
        !is_nil(tmdb_year) and abs(query_year - tmdb_year) <= 1 -> 0.8
        !is_nil(imdb_year) and abs(query_year - imdb_year) <= 1 -> 0.8
        true -> 0.3
      end

    # Bridge bonus - successful IMDB web bridge is a strong signal
    # Slightly higher than OMDb bridge since IMDB AKA data is very reliable
    bridge_bonus = 0.18

    title_score * 0.42 + year_score * 0.40 + bridge_bonus
  end

  # Calculate title similarity score
  defp calculate_title_score(result, query) do
    query_titles =
      [query[:title], query[:original_title], query[:polish_title]]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.map(&String.downcase/1)

    result_titles =
      [result[:title], result[:original_title], result[:imdb_title]]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.map(&String.downcase/1)

    if Enum.empty?(query_titles) or Enum.empty?(result_titles) do
      0.0
    else
      for qt <- query_titles, rt <- result_titles, reduce: 0.0 do
        acc -> max(acc, String.jaro_distance(qt, rt))
      end
    end
  end

  # Calculate year match score
  defp calculate_year_score(result, query) do
    query_year = query[:year]

    result_year =
      case result[:release_date] do
        nil ->
          result[:imdb_year]

        "" ->
          result[:imdb_year]

        date when is_binary(date) ->
          case String.slice(date, 0..3) do
            "" -> result[:imdb_year]
            year_str -> String.to_integer(year_str)
          end
      end

    cond do
      is_nil(query_year) or is_nil(result_year) -> 0.5
      query_year == result_year -> 1.0
      abs(query_year - result_year) == 1 -> 0.8
      abs(query_year - result_year) == 2 -> 0.5
      true -> 0.0
    end
  end
end
