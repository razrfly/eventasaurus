defmodule EventasaurusDiscovery.Movies.Providers.OmdbProvider do
  @moduledoc """
  OMDb (Open Movie Database) provider implementation.

  This is a secondary/fallback provider that bridges to TMDB via IMDB IDs.
  Useful for:

  - Polish titles that map better to IMDB
  - Older/classic films with better OMDb coverage
  - Cross-referencing movie identities via IMDB ID

  ## Priority

  Priority: 20 (secondary/fallback provider)

  ## Bridge Strategy

  When OMDb finds a movie, we use its IMDB ID to look up the corresponding
  TMDB ID via TMDB's `/find` endpoint. This ensures all results ultimately
  have TMDB IDs for consistency.

  ## Supported Languages

  OMDb primarily supports English titles but can match some international titles.
  """

  @behaviour EventasaurusDiscovery.Movies.Provider

  require Logger

  alias EventasaurusDiscovery.Movies.OmdbService
  alias EventasaurusWeb.Services.TmdbService

  # Provider configuration
  # NOTE: Must be a string for Ecto to cast to :string type in Movie schema
  @provider_name "omdb"
  @provider_priority 20
  # OMDb is primarily English
  @supported_languages ~w(en)

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
    year = Keyword.get(opts, :year) || Map.get(query, :year)

    # Build list of titles to search
    titles = build_search_titles(query)

    # Build OMDb search options
    omdb_opts = if year, do: [year: year], else: []

    # Try each title until we find results
    result =
      Enum.find_value(titles, fn title ->
        case search_and_bridge(title, omdb_opts, query) do
          {:ok, [_ | _] = results} -> {:ok, results}
          _ -> nil
        end
      end)

    result || {:ok, []}
  end

  @impl true
  def get_details(imdb_id) when is_binary(imdb_id) do
    case OmdbService.get_by_imdb_id(imdb_id) do
      {:ok, details} ->
        {:ok, format_details(details)}

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
      query[:original_title],
      query[:title],
      query[:polish_title]
    ]
    |> Enum.filter(&(&1 && &1 != ""))
    |> Enum.uniq()
  end

  # Search OMDb and bridge results to TMDB
  defp search_and_bridge(title, opts, query) do
    case OmdbService.search(title, opts) do
      {:ok, %{results: [_ | _] = results}} ->
        # Bridge top results to TMDB (limit to 3 to avoid excessive API calls)
        bridged =
          results
          |> Enum.take(3)
          |> Enum.flat_map(&bridge_to_tmdb(&1, query))

        {:ok, bridged}

      {:ok, %{results: []}} ->
        {:error, :no_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Bridge a single OMDb result to TMDB
  defp bridge_to_tmdb(omdb_result, query) do
    imdb_id = omdb_result[:imdb_id]

    if imdb_id do
      case TmdbService.find_by_external_id(imdb_id, "imdb_id") do
        {:ok, %{movie_results: [tmdb_movie | _]}} ->
          Logger.info("🔗 OMDb→TMDB bridge: #{imdb_id} → TMDB #{tmdb_movie["id"]}")

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
              bridge_source: :omdb,
              confidence: calculate_confidence_for_bridged(tmdb_movie, omdb_result, query)
            }
          ]

        _ ->
          Logger.debug("OMDb result #{imdb_id} not found in TMDB")
          []
      end
    else
      []
    end
  end

  # Format details from OmdbService response
  defp format_details(details) do
    %{
      imdb_id: details[:imdb_id],
      title: details[:title],
      year: details[:year],
      runtime: details[:runtime],
      director: details[:director],
      actors: details[:actors],
      plot: details[:plot],
      poster_url: details[:poster_url],
      genres: details[:genres],
      country: details[:country],
      language: details[:language],
      imdb_rating: details[:imdb_rating],
      imdb_votes: details[:imdb_votes],
      metascore: details[:metascore],
      provider: @provider_name
    }
  end

  # Calculate confidence score (0.0 - 1.0)
  defp calculate_confidence(result, query) do
    # Title similarity (50%)
    title_score = calculate_title_score(result, query) * 0.50

    # Year matching (30%)
    year_score = calculate_year_score(result, query) * 0.30

    # Bridge bonus (20%) - if we successfully bridged from OMDb, add confidence
    bridge_score = if result[:bridge_source] == :omdb, do: 0.20, else: 0.10

    title_score + year_score + bridge_score
  end

  # Calculate confidence for bridged results (uses both TMDB and OMDb data)
  defp calculate_confidence_for_bridged(tmdb_movie, omdb_result, query) do
    # Title similarity against query
    query_titles =
      [query[:title], query[:original_title], query[:polish_title]]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.map(&String.downcase/1)

    tmdb_titles =
      [tmdb_movie["title"], tmdb_movie["original_title"]]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.map(&String.downcase/1)

    omdb_title =
      if omdb_result[:title], do: [String.downcase(omdb_result[:title])], else: []

    all_result_titles = tmdb_titles ++ omdb_title

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

        date when is_binary(date) and byte_size(date) >= 4 ->
          case Integer.parse(String.slice(date, 0..3)) do
            {year, _} -> year
            :error -> nil
          end

        _ ->
          nil
      end

    omdb_year = parse_omdb_year(omdb_result[:year])

    year_score =
      cond do
        is_nil(query_year) -> 0.5
        query_year == tmdb_year -> 1.0
        query_year == omdb_year -> 1.0
        !is_nil(tmdb_year) and abs(query_year - tmdb_year) <= 1 -> 0.8
        !is_nil(omdb_year) and abs(query_year - omdb_year) <= 1 -> 0.8
        true -> 0.3
      end

    # Bridge bonus - successful bridge is a strong signal
    bridge_bonus = 0.15

    title_score * 0.45 + year_score * 0.40 + bridge_bonus
  end

  # Parse OMDb year (can be "2024" or "2020–2024" for series)
  defp parse_omdb_year(nil), do: nil

  defp parse_omdb_year(year) when is_binary(year) do
    case Integer.parse(year) do
      {y, _} -> y
      :error -> nil
    end
  end

  defp parse_omdb_year(year) when is_integer(year), do: year

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
          nil

        "" ->
          nil

        date when is_binary(date) and byte_size(date) >= 4 ->
          case Integer.parse(String.slice(date, 0..3)) do
            {year, _} -> year
            :error -> nil
          end

        _ ->
          nil
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
