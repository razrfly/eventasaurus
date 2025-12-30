defmodule EventasaurusDiscovery.Movies.MovieLookupService do
  @moduledoc """
  Unified movie lookup service that orchestrates multiple providers.

  This service provides a single entry point for all movie lookups across
  the application, replacing direct usage of TmdbMatcher in individual sources.

  ## Features

  - **Multi-provider search**: Queries TMDB (primary), OMDb (secondary), IMDB web (tertiary)
  - **Intelligent fallback**: Tries secondary/tertiary providers when primary fails
  - **Confidence aggregation**: Combines scores across providers
  - **Result deduplication**: Merges results from multiple providers
  - **Caching**: Reduces API calls for repeated lookups
  - **Comprehensive logging**: Tracks success/failure rates and timing

  ## Usage

      query = %{
        polish_title: "Gladiator 2",
        original_title: "Gladiator II",
        year: 2024
      }

      case MovieLookupService.lookup(query) do
        {:ok, tmdb_id, confidence} ->
          # High confidence match found
          IO.puts("Found TMDB ID: \#{tmdb_id} with \#{confidence * 100}% confidence")

        {:needs_review, candidates} ->
          # Multiple possible matches need manual review
          IO.inspect(candidates)

        {:error, :no_results} ->
          # No matches found across all providers
          IO.puts("Movie not found")
      end

  ## Configuration

  Providers and thresholds can be configured in config.exs:

      config :eventasaurus_discovery, :movie_lookup,
        providers: [:tmdb, :omdb, :imdb],
        confidence_threshold: 0.7,
        review_threshold: 0.5,
        cache_ttl: :timer.hours(24)

  ## Providers

  - **TmdbProvider** (priority: 10): Primary provider with comprehensive data
  - **OmdbProvider** (priority: 20): Secondary that bridges to TMDB via IMDB ID
  - **ImdbProvider** (priority: 30): Tertiary that uses Zyte web scraping for IMDB AKA data
  """

  require Logger

  alias EventasaurusDiscovery.Movies.Providers.{TmdbProvider, OmdbProvider, ImdbProvider}
  alias EventasaurusDiscovery.Movies.MovieStore

  # Configuration defaults
  # ImdbProvider (priority 30) is tried last as it uses Zyte web scraping
  @default_providers [TmdbProvider, OmdbProvider, ImdbProvider]
  @default_confidence_threshold 0.70
  @default_review_threshold 0.50
  @default_cache_ttl :timer.hours(24)

  # ETS table for caching
  @cache_table :movie_lookup_cache

  @doc """
  Look up a movie across all configured providers.

  ## Parameters

  - `query` - A map with search criteria:
    - `:title` - Generic title
    - `:original_title` - Original (English) title
    - `:polish_title` - Polish title
    - `:year` - Release year
    - `:runtime` - Runtime in minutes
    - `:director` - Director name
    - `:country` - Country of origin
    - `:imdb_id` - IMDB ID (if known)
    - `:tmdb_id` - TMDB ID (if known)

  - `opts` - Optional parameters:
    - `:providers` - List of provider modules to use
    - `:language` - Preferred language for results
    - `:skip_cache` - Skip cache lookup if true
    - `:confidence_threshold` - Override default threshold

  ## Returns

  - `{:ok, tmdb_id, confidence, provider, extra}` - High confidence match with provider name and extra data
  - `{:needs_review, candidates}` - Matches need manual review
  - `{:error, reason}` - Lookup failed

  The `provider` field indicates which provider found the match:
  - `"tmdb"` - TMDB (free, primary)
  - `"omdb"` - OMDb (paid, secondary)
  - `"imdb"` - IMDB via Zyte (paid, tertiary)

  The `extra` map contains additional data from the match:
  - `:imdb_id` - IMDB ID if available (e.g., "tt0172495")
  """
  def lookup(query, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    # Check cache first
    cache_key = build_cache_key(query)
    skip_cache = Keyword.get(opts, :skip_cache, false)

    result =
      if skip_cache do
        do_lookup(query, opts)
      else
        case get_from_cache(cache_key) do
          {:ok, cached_result} ->
            Logger.debug("🎯 Cache hit for movie lookup")
            cached_result

          :miss ->
            result = do_lookup(query, opts)
            put_in_cache(cache_key, result)
            result
        end
      end

    # Log timing
    duration = System.monotonic_time(:millisecond) - start_time
    log_lookup_result(query, result, duration)

    result
  end

  @doc """
  Look up a movie and create/find it in the database.

  This combines lookup with database persistence, returning a Movie struct.

  ## Parameters

  Same as `lookup/2`

  ## Returns

  - `{:ok, movie}` - Movie struct from database
  - `{:needs_review, candidates}` - Matches need manual review
  - `{:error, reason}` - Lookup or database operation failed
  """
  def find_or_create_movie(query, opts \\ []) do
    case lookup(query, opts) do
      {:ok, tmdb_id, confidence, provider, extra} ->
        Logger.info(
          "📀 Creating/finding movie for TMDB #{tmdb_id} (#{trunc(confidence * 100)}% via #{provider})"
        )

        # Pass provider and imdb_id to MovieStore to store in dedicated columns
        attrs = %{matched_by_provider: provider}
        attrs = if extra[:imdb_id], do: Map.put(attrs, :imdb_id, extra[:imdb_id]), else: attrs

        case MovieStore.find_or_create_by_tmdb_id(tmdb_id, attrs) do
          {:ok, movie} -> {:ok, movie}
          {:error, reason} -> {:error, {:database_error, reason}}
        end

      {:needs_review, _candidates} = result ->
        result

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Search all providers and return aggregated results.

  Unlike `lookup/2`, this returns all results from all providers without
  selecting a best match. Useful for manual review or debugging.

  ## Returns

  - `{:ok, results}` - List of all results with provider metadata
  - `{:error, reason}` - All providers failed
  """
  def search_all(query, opts \\ []) do
    providers = get_providers(opts)

    results =
      providers
      |> Enum.sort_by(& &1.priority())
      |> Enum.flat_map(fn provider ->
        case provider.search(query, opts) do
          {:ok, results} -> results
          {:error, _} -> []
        end
      end)
      |> deduplicate_results()
      |> Enum.sort_by(& &1[:confidence], :desc)

    if Enum.empty?(results) do
      {:error, :no_results}
    else
      {:ok, results}
    end
  end

  @doc """
  Initialize the cache table.

  Call this during application startup.
  """
  def init_cache do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
      Logger.info("📦 MovieLookupService cache initialized")
    end

    :ok
  end

  @doc """
  Clear the lookup cache.
  """
  def clear_cache do
    if :ets.whereis(@cache_table) != :undefined do
      :ets.delete_all_objects(@cache_table)
      Logger.info("🧹 MovieLookupService cache cleared")
    end

    :ok
  end

  @doc """
  Get cache statistics.
  """
  def cache_stats do
    if :ets.whereis(@cache_table) != :undefined do
      info = :ets.info(@cache_table)

      %{
        size: Keyword.get(info, :size, 0),
        memory: Keyword.get(info, :memory, 0)
      }
    else
      %{size: 0, memory: 0}
    end
  end

  # Private functions

  defp do_lookup(query, opts) do
    # If we already have a TMDB ID, just validate it exists
    if query[:tmdb_id] do
      validate_tmdb_id(query[:tmdb_id])
    else
      # Normalize query titles before searching to improve match rates
      normalized_query = normalize_query_for_search(query)
      search_providers(normalized_query, opts)
    end
  end

  @doc """
  Normalize query titles for better matching.

  Strips language/dubbing suffixes that prevent TMDB matches:
  - "ukraiński dubbing" (Ukrainian dubbing)
  - "dubbing" suffix
  - "napisy polskie" (Polish subtitles)
  - "wersja polska" (Polish version)
  - "3D" suffix
  - Year suffixes at end of title
  """
  @spec normalize_query_for_search(map()) :: map()
  def normalize_query_for_search(query) do
    normalized_polish = normalize_title_for_search(query[:polish_title])
    normalized_original = normalize_title_for_search(query[:original_title])
    normalized_title = normalize_title_for_search(query[:title])

    # Log normalization for debugging
    if normalized_polish != query[:polish_title] do
      Logger.info("🔄 Title normalized: \"#{query[:polish_title]}\" → \"#{normalized_polish}\"")
    end

    query
    |> Map.put(:polish_title, normalized_polish)
    |> Map.put(:original_title, normalized_original)
    |> Map.put(:title, normalized_title)
    # Keep original titles for reference
    |> Map.put(:original_polish_title, query[:polish_title])
    |> Map.put(:original_original_title, query[:original_title])
  end

  defp normalize_title_for_search(nil), do: nil
  defp normalize_title_for_search(""), do: ""

  defp normalize_title_for_search(title) when is_binary(title) do
    title
    # Remove Ukrainian dubbing suffix (most common issue)
    |> String.replace(~r/\s+ukraiński\s+dubbing$/i, "")
    |> String.replace(~r/\s+ukrainian\s+dubbing$/i, "")
    # Remove generic dubbing suffix
    |> String.replace(~r/\s+dubbing$/i, "")
    # Remove Polish subtitles suffix
    |> String.replace(~r/\s+napisy\s+polskie$/i, "")
    |> String.replace(~r/\s+polish\s+subtitles$/i, "")
    # Remove Polish version suffix
    |> String.replace(~r/\s+wersja\s+polska$/i, "")
    # Remove 3D suffix (can interfere with matching)
    |> String.replace(~r/\s+3D$/i, "")
    # Remove 2D suffix as well
    |> String.replace(~r/\s+2D$/i, "")
    # Remove year suffix at end (e.g., "Movie Title 2024")
    |> String.replace(~r/\s+\(\d{4}\)$/, "")
    # Remove "Kolekcja" (Collection) prefix
    |> String.replace(~r/^Kolekcja\s+/i, "")
    # "w kinie:" (in cinema) → space
    |> String.replace(~r/\s+w\s+kinie:\s+/i, " ")
    # Remove Polish exclamations like "górą!"
    |> String.replace(~r/\s+górą!$/i, "")
    # Remove screening format indicators (IMAX, Dolby, etc.)
    |> String.replace(~r/\s+IMAX$/i, "")
    |> String.replace(~r/\s+Dolby(\s+Atmos)?$/i, "")
    |> String.replace(~r/\s+4DX$/i, "")
    |> String.replace(~r/\s+ScreenX$/i, "")
    # Remove Polish screening type suffixes (NAP = napisy, KNT, DKF, PKF)
    |> String.replace(~r/\s+[-–]\s*(NAP|KNT|DKF|PKF)\s*$/i, "")
    |> String.replace(~r/\s+(NAP|KNT|DKF|PKF)\s*$/i, "")
    # Remove "i inne opowieści" (and other stories) - helps with compilation titles
    |> String.replace(~r/:\s+[Śś]więta\s+i\s+inne\s+opowie[śs]ci$/i, "")
    |> String.replace(~r/\s+i\s+inne\s+opowie[śs]ci$/i, "")
    # Remove "Święta z" (Christmas with) prefix - helps find the main film
    |> String.replace(~r/^[Śś]więta\s+z\s+/i, "")
    # Remove season/episode indicators
    |> String.replace(~r/\s+[-–]\s*sezon\s+\d+$/i, "")
    |> String.replace(~r/\s+s\d+e\d+$/i, "")
    # Clean up extra whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp validate_tmdb_id(tmdb_id) do
    case TmdbProvider.get_details(tmdb_id) do
      {:ok, _details} ->
        # Direct TMDB ID validation counts as TMDB provider match
        # No imdb_id available from direct validation
        {:ok, tmdb_id, 1.0, "tmdb", %{imdb_id: nil}}

      {:error, _reason} ->
        {:error, :invalid_tmdb_id}
    end
  end

  defp search_providers(query, opts) do
    providers = get_providers(opts)
    confidence_threshold = get_confidence_threshold(opts)
    review_threshold = get_review_threshold(opts)

    # Search providers in priority order
    results =
      providers
      |> Enum.sort_by(& &1.priority())
      |> search_until_confident(query, opts, confidence_threshold)

    # Analyze results
    case results do
      [] ->
        {:error, :no_results}

      [best | _rest] = all ->
        confidence = best[:confidence] || 0.0
        tmdb_id = best[:tmdb_id] || best[:id]
        # Extract provider from the best match (providers add :provider to results)
        provider = best[:provider] || "unknown"
        # Extract extra data like imdb_id (OMDb/IMDB providers include this)
        extra = %{imdb_id: best[:imdb_id]}

        cond do
          confidence >= confidence_threshold ->
            {:ok, tmdb_id, confidence, provider, extra}

          confidence >= review_threshold ->
            {:needs_review, all}

          true ->
            {:error, :low_confidence}
        end
    end
  end

  # Search providers until we find a confident match
  defp search_until_confident([], _query, _opts, _threshold), do: []

  defp search_until_confident([provider | rest], query, opts, threshold) do
    case provider.search(query, opts) do
      {:ok, [_ | _] = results} ->
        # Sort by confidence
        sorted = Enum.sort_by(results, & &1[:confidence], :desc)
        best = List.first(sorted)

        if best[:confidence] && best[:confidence] >= threshold do
          # Found confident match, stop searching
          Logger.info(
            "✅ #{provider.name()} found confident match: #{best[:title]} (#{trunc(best[:confidence] * 100)}%)"
          )

          sorted
        else
          # Continue searching other providers
          Logger.debug("⏭️ #{provider.name()} best match below threshold, trying next provider")

          more_results = search_until_confident(rest, query, opts, threshold)
          deduplicate_results(sorted ++ more_results)
        end

      {:ok, []} ->
        Logger.debug("⏭️ #{provider.name()} returned no results, trying next provider")
        search_until_confident(rest, query, opts, threshold)

      {:error, reason} ->
        Logger.warning("⚠️ #{provider.name()} failed: #{inspect(reason)}, trying next provider")
        search_until_confident(rest, query, opts, threshold)
    end
  end

  # Deduplicate results by TMDB ID
  defp deduplicate_results(results) do
    results
    |> Enum.group_by(fn r -> r[:tmdb_id] || r[:id] end)
    |> Enum.map(fn {_id, group} ->
      # Keep the result with highest confidence
      Enum.max_by(group, & &1[:confidence], fn -> List.first(group) end)
    end)
    |> Enum.sort_by(& &1[:confidence], :desc)
  end

  # Cache functions

  defp build_cache_key(query) do
    # Build a deterministic cache key from query
    key_parts =
      [
        query[:title],
        query[:original_title],
        query[:polish_title],
        query[:year],
        query[:imdb_id],
        query[:tmdb_id]
      ]
      |> Enum.filter(&(&1 != nil))
      |> Enum.join("|")

    :erlang.phash2(key_parts)
  end

  defp get_from_cache(key) do
    if :ets.whereis(@cache_table) != :undefined do
      case :ets.lookup(@cache_table, key) do
        [{^key, result, expires_at}] ->
          if System.monotonic_time(:millisecond) < expires_at do
            {:ok, result}
          else
            :ets.delete(@cache_table, key)
            :miss
          end

        [] ->
          :miss
      end
    else
      :miss
    end
  end

  defp put_in_cache(key, result) do
    if :ets.whereis(@cache_table) != :undefined do
      ttl = get_cache_ttl()
      expires_at = System.monotonic_time(:millisecond) + ttl
      :ets.insert(@cache_table, {key, result, expires_at})
    end

    :ok
  end

  # Configuration helpers

  defp get_providers(opts) do
    Keyword.get(opts, :providers) ||
      Application.get_env(:eventasaurus_discovery, :movie_lookup, [])[:providers] ||
      @default_providers
  end

  defp get_confidence_threshold(opts) do
    Keyword.get(opts, :confidence_threshold) ||
      Application.get_env(:eventasaurus_discovery, :movie_lookup, [])[:confidence_threshold] ||
      @default_confidence_threshold
  end

  defp get_review_threshold(opts) do
    Keyword.get(opts, :review_threshold) ||
      Application.get_env(:eventasaurus_discovery, :movie_lookup, [])[:review_threshold] ||
      @default_review_threshold
  end

  defp get_cache_ttl do
    Application.get_env(:eventasaurus_discovery, :movie_lookup, [])[:cache_ttl] ||
      @default_cache_ttl
  end

  # Logging

  defp log_lookup_result(query, result, duration) do
    title = query[:polish_title] || query[:original_title] || query[:title] || "unknown"

    case result do
      {:ok, tmdb_id, confidence, provider, extra} ->
        imdb_suffix = if extra[:imdb_id], do: ", IMDB: #{extra[:imdb_id]}", else: ""

        Logger.info(
          "🎬 MovieLookup: \"#{title}\" → TMDB #{tmdb_id} (#{trunc(confidence * 100)}% via #{provider}#{imdb_suffix}) in #{duration}ms"
        )

      {:needs_review, candidates} ->
        Logger.warning(
          "🔍 MovieLookup: \"#{title}\" needs review (#{length(candidates)} candidates) in #{duration}ms"
        )

      {:error, reason} ->
        Logger.warning("❌ MovieLookup: \"#{title}\" failed: #{inspect(reason)} in #{duration}ms")
    end
  end
end
