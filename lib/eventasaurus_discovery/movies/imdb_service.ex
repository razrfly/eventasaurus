defmodule EventasaurusDiscovery.Movies.ImdbService do
  @moduledoc """
  Service for searching IMDB via web scraping using Crawlbase.

  IMDB's web search supports AKA (Also Known As) data, making it effective
  for matching Polish movie titles to their original English titles.
  This is particularly useful for:

  - Classic films with Polish translations (e.g., "Siedmiu samurajów" → "Seven Samurai")
  - Well-known international films (e.g., "To wspaniałe życie" → "It's a Wonderful Life")
  - Movies where TMDB/OMDb title search fails but IMDB AKA data exists

  ## How It Works

  1. Constructs IMDB search URL with the Polish title
  2. Uses Crawlbase JavaScript rendering to fetch the search results page
  3. Parses the HTML to extract IMDB IDs and English titles
  4. Returns results that can be bridged to TMDB via the find endpoint

  ## Configuration

  Requires `CRAWLBASE_JS_API_KEY` environment variable to be set.
  Uses the HTTP abstraction layer with `:imdb` source configuration.

  ## Usage

      # Search IMDB with a Polish title
      {:ok, results} = ImdbService.search("Siedmiu samurajów")
      #=> {:ok, [%{imdb_id: "tt0047478", title: "Seven Samurai", year: 1954}]}

      # Search with year filter
      {:ok, results} = ImdbService.search("To wspaniałe życie", year: 1946)
      #=> {:ok, [%{imdb_id: "tt0038650", title: "It's a Wonderful Life", year: 1946}]}

  ## Limitations

  - Requires Crawlbase API (costs per request)
  - Only finds movies that exist in IMDB database
  - Obscure local content may not have IMDB entries
  - Rate limited by Crawlbase API
  """

  require Logger

  alias EventasaurusDiscovery.Http.Client, as: HttpClient
  alias EventasaurusDiscovery.Http.Adapters.Crawlbase

  @imdb_search_url "https://www.imdb.com/find/"
  # Crawlbase browser rendering can take 30-60 seconds for IMDB
  @timeout 60_000

  @doc """
  Search IMDB for movies matching the given title.

  Uses IMDB's web search which includes AKA (Also Known As) data,
  making it effective for finding movies by their Polish titles.

  ## Parameters

  - `title` - The movie title to search for (can be in Polish or any language)
  - `opts` - Optional parameters:
    - `:year` - Filter results by release year
    - `:limit` - Maximum number of results to return (default: 5)

  ## Returns

  - `{:ok, results}` - List of matching movies with IMDB IDs
  - `{:error, reason}` - Search failed

  ## Examples

      iex> ImdbService.search("Siedmiu samurajów")
      {:ok, [%{imdb_id: "tt0047478", title: "Seven Samurai", year: 1954, type: :movie}]}

      iex> ImdbService.search("To wspaniałe życie", year: 1946)
      {:ok, [%{imdb_id: "tt0038650", title: "It's a Wonderful Life", year: 1946, type: :movie}]}
  """
  def search(title, opts \\ []) when is_binary(title) do
    if Crawlbase.available_for_mode?(:javascript) do
      do_search(title, opts)
    else
      Logger.warning("ImdbService: Crawlbase JS API not configured, skipping IMDB search")
      {:error, :crawlbase_not_configured}
    end
  end

  @doc """
  Check if the IMDB service is available (Crawlbase JS API configured).
  """
  def available? do
    Crawlbase.available_for_mode?(:javascript)
  end

  # Private implementation

  defp do_search(title, opts) do
    year = Keyword.get(opts, :year)
    limit = Keyword.get(opts, :limit, 5)

    url = build_search_url(title)

    Logger.info(
      "🔍 ImdbService: Searching IMDB for \"#{title}\"#{if year, do: " (#{year})", else: ""}"
    )

    # Use HTTP abstraction layer with :imdb source configuration
    # This routes through Crawlbase with JavaScript rendering
    case HttpClient.fetch(url,
           source: :imdb,
           timeout: @timeout,
           recv_timeout: @timeout,
           mode: :javascript
         ) do
      {:ok, html, metadata} ->
        Logger.debug(
          "ImdbService: Received #{byte_size(html)} bytes in #{metadata[:duration_ms]}ms via #{metadata[:adapter]}"
        )

        results =
          html
          |> parse_search_results()
          |> filter_movies_only()
          |> maybe_filter_by_year(year)
          |> Enum.take(limit)

        Logger.info("🎬 ImdbService: Found #{length(results)} results for \"#{title}\"")

        {:ok, results}

      {:error, :not_configured} ->
        {:error, :crawlbase_not_configured}

      {:error, {:rate_limit, retry_after}} ->
        Logger.warning("ImdbService: Rate limited, retry after #{retry_after}s")
        {:error, {:rate_limited, retry_after}}

      {:error, {:timeout, _type}} ->
        Logger.warning("ImdbService: Request timeout for \"#{title}\"")
        {:error, :timeout}

      {:error, {:crawlbase_error, status, message}} ->
        Logger.error("ImdbService: Crawlbase error #{status}: #{message}")
        {:error, {:crawlbase_error, status, message}}

      {:error, {:all_adapters_failed, blocked_by}} ->
        Logger.error("ImdbService: All adapters failed: #{inspect(blocked_by)}")
        {:error, {:all_adapters_failed, blocked_by}}

      {:error, reason} ->
        Logger.error("ImdbService: Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_search_url(title) do
    # IMDB search URL with type filter for titles (tt = title)
    # The 's=tt' parameter restricts to title searches
    encoded_title = URI.encode(title)
    "#{@imdb_search_url}?q=#{encoded_title}&s=tt&ttype=ft"
  end

  @doc false
  # Parse IMDB search results HTML to extract movie data
  # Made public for testing purposes
  def parse_search_results(html) do
    # IMDB search results have a specific structure
    # Each result is in a list item with class containing "ipc-metadata-list-summary-item"
    # The link contains the IMDB ID in href like "/title/tt0047478/"
    # Title and year are in nested elements

    # Pattern 1: Modern IMDB search results (2024+ layout)
    # Look for result items containing title links
    results = parse_modern_layout(html)

    if Enum.empty?(results) do
      # Fallback: Try legacy layout parsing
      parse_legacy_layout(html)
    else
      results
    end
  end

  defp parse_modern_layout(html) do
    # Modern IMDB (2024+) uses different patterns:
    # 1. aria-label="View title page for {Title}" on overlay links
    # 2. href="/title/tt{id}/" for the actual link
    # 3. Year may be in nearby span elements

    # Try multiple extraction strategies and merge results

    # Strategy 1: Extract from aria-label (most reliable for modern layout)
    # Pattern: <a ... href="/title/tt0047478/..." aria-label="View title page for Seven Samurai">
    aria_results =
      ~r/<a[^>]*href="\/title\/(tt\d+)\/[^"]*"[^>]*aria-label="View title page for ([^"]+)"/i
      |> Regex.scan(html)
      |> Enum.map(fn [_full, imdb_id, title] ->
        year = extract_year_near_title(html, imdb_id)
        type = determine_type(html, imdb_id)

        %{
          imdb_id: imdb_id,
          title: String.trim(title),
          year: year,
          type: type
        }
      end)

    # Strategy 2: Extract from link text (for links with visible text)
    # Pattern: <a href="/title/tt0047478/">Seven Samurai</a>
    text_results =
      ~r/<a[^>]*href="\/title\/(tt\d+)\/[^"]*"[^>]*>([^<]+)<\/a>/i
      |> Regex.scan(html)
      |> Enum.filter(fn [_full, _id, text] ->
        # Filter out empty or placeholder text
        trimmed = String.trim(text)
        trimmed != "" and not String.starts_with?(trimmed, "<") and String.length(trimmed) > 1
      end)
      |> Enum.map(fn [_full, imdb_id, title] ->
        year = extract_year_near_title(html, imdb_id)
        type = determine_type(html, imdb_id)

        %{
          imdb_id: imdb_id,
          title: String.trim(title),
          year: year,
          type: type
        }
      end)

    # Merge and deduplicate, preferring aria-label titles (more complete)
    (aria_results ++ text_results)
    |> Enum.uniq_by(& &1.imdb_id)
  end

  defp parse_legacy_layout(html) do
    # Legacy IMDB search results pattern
    # <td class="result_text">
    #   <a href="/title/tt0047478/">Seven Samurai</a> (1954)
    # </td>

    # Use sigil with different delimiter to avoid escaping issues
    pattern = ~r/<a[^>]*href="\/title\/(tt\d+)\/[^"]*"[^>]*>([^<]+)<\/a>\s*\((\d{4})\)/i

    pattern
    |> Regex.scan(html)
    |> Enum.map(fn [_full, imdb_id, title, year] ->
      %{
        imdb_id: imdb_id,
        title: String.trim(title),
        year: parse_year(year),
        type: :movie
      }
    end)
    |> Enum.uniq_by(& &1.imdb_id)
  end

  defp extract_year_near_title(html, imdb_id) do
    # Look for year pattern near the IMDB ID
    # Pattern: title link followed by year in parentheses or span

    # Try to find a section containing this IMDB ID and extract year
    # Use Regex.compile!/2 to handle dynamic pattern with parentheses
    escaped_id = Regex.escape(imdb_id)
    pattern = Regex.compile!("#{escaped_id}[^<]*</a>[^(]*\\((\\d{4})\\)", "i")

    case Regex.run(pattern, html) do
      [_, year] ->
        parse_year(year)

      nil ->
        # Alternative: look for year in a span after the link
        alt_pattern = Regex.compile!("#{escaped_id}[^<]*</a>.*?<span[^>]*>(\\d{4})</span>", "is")

        case Regex.run(alt_pattern, html) do
          [_, year] -> parse_year(year)
          nil -> nil
        end
    end
  end

  defp determine_type(html, imdb_id) do
    # Try to determine if this is a movie, TV series, etc.
    # Look for type indicators near the IMDB ID

    escaped_id = Regex.escape(imdb_id)

    context_pattern =
      Regex.compile!("#{escaped_id}[^<]*</a>[^<]*(?:<[^>]*>([^<]*)</[^>]*>)?", "i")

    case Regex.run(context_pattern, html) do
      [_, type_hint] when is_binary(type_hint) ->
        type_hint_lower = String.downcase(type_hint)

        cond do
          String.contains?(type_hint_lower, "series") -> :tv_series
          String.contains?(type_hint_lower, "episode") -> :episode
          String.contains?(type_hint_lower, "short") -> :short
          String.contains?(type_hint_lower, "video") -> :video
          true -> :movie
        end

      _ ->
        :movie
    end
  end

  defp filter_movies_only(results) do
    # Filter to only movies (not TV series, episodes, etc.)
    Enum.filter(results, fn result ->
      result.type == :movie or result.type == nil
    end)
  end

  defp maybe_filter_by_year(results, nil), do: results

  defp maybe_filter_by_year(results, year) when is_integer(year) do
    # Filter by year with ±1 year tolerance
    Enum.filter(results, fn result ->
      case result.year do
        nil -> true
        result_year -> abs(result_year - year) <= 1
      end
    end)
  end

  defp parse_year(nil), do: nil
  defp parse_year(year) when is_integer(year), do: year

  defp parse_year(year) when is_binary(year) do
    case Integer.parse(year) do
      {y, _} -> y
      :error -> nil
    end
  end
end
