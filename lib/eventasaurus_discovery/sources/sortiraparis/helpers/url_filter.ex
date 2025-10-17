defmodule EventasaurusDiscovery.Sources.Sortiraparis.Helpers.UrlFilter do
  @moduledoc """
  Filter and classify URLs from Sortiraparis sitemaps.

  ## Responsibilities

  1. Filter event URLs from general content URLs
  2. Deduplicate URLs
  3. Apply configurable filters (categories, exclude patterns)
  4. Track filtering statistics
  5. Handle URL variations (trailing slashes, query parameters, etc.)

  ## URL Classification Strategy

  Uses `Config.is_event_url?/1` for classification:
  - **Include**: URLs with event category segments (concerts, exhibits, shows, theater)
  - **Exclude**: URLs with non-event patterns (guides, news, where-to-eat, best-of)

  ## Usage

      iex> urls = ["https://www.sortiraparis.com/concerts/articles/123-event",
      ...>         "https://www.sortiraparis.com/guides/best-restaurants"]
      iex> UrlFilter.filter_event_urls(urls)
      {:ok, ["https://www.sortiraparis.com/concerts/articles/123-event"], %{total: 2, filtered: 1, excluded: 1}}
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Sortiraparis.Config

  @doc """
  Filter list of URLs to only include event URLs.

  Returns a tuple with:
  - List of event URLs
  - Statistics map with counts

  ## Examples

      iex> filter_event_urls(["https://www.sortiraparis.com/concerts/articles/123-event"])
      {:ok, ["https://www.sortiraparis.com/concerts/articles/123-event"], %{total: 1, filtered: 1, excluded: 0}}

      iex> filter_event_urls([])
      {:ok, [], %{total: 0, filtered: 0, excluded: 0}}
  """
  def filter_event_urls(urls) when is_list(urls) do
    stats = %{
      total: length(urls),
      filtered: 0,
      excluded: 0,
      duplicates_removed: 0
    }

    # Deduplicate first
    unique_urls = Enum.uniq(urls)
    duplicates_removed = length(urls) - length(unique_urls)

    # Filter event URLs
    event_urls =
      unique_urls
      |> Enum.filter(&Config.is_event_url?/1)

    filtered_count = length(event_urls)
    excluded_count = length(unique_urls) - filtered_count

    final_stats = %{
      stats
      | filtered: filtered_count,
        excluded: excluded_count,
        duplicates_removed: duplicates_removed
    }

    Logger.debug("""
    URL Filtering Stats:
    - Total URLs: #{stats.total}
    - Duplicates removed: #{duplicates_removed}
    - Event URLs: #{filtered_count}
    - Excluded: #{excluded_count}
    """)

    {:ok, event_urls, final_stats}
  end

  def filter_event_urls(_), do: {:error, :invalid_url_list}

  @doc """
  Filter URLs with custom include/exclude patterns.

  ## Options

  - `:include_patterns` - List of patterns that must be present (default: `Config.event_categories/0`)
  - `:exclude_patterns` - List of patterns that must NOT be present (default: `Config.exclude_patterns/0`)
  - `:case_sensitive` - Whether pattern matching is case-sensitive (default: `false`)

  ## Examples

      iex> filter_with_patterns(urls, include_patterns: ["concerts"], exclude_patterns: ["guides"])
      {:ok, filtered_urls, stats}
  """
  def filter_with_patterns(urls, options \\ [])

  def filter_with_patterns(urls, options) when is_list(urls) do
    include_patterns = Keyword.get(options, :include_patterns, Config.event_categories())
    exclude_patterns = Keyword.get(options, :exclude_patterns, Config.exclude_patterns())
    case_sensitive = Keyword.get(options, :case_sensitive, false)

    stats = %{
      total: length(urls),
      filtered: 0,
      excluded: 0,
      duplicates_removed: 0
    }

    # Deduplicate
    unique_urls = Enum.uniq(urls)
    duplicates_removed = length(urls) - length(unique_urls)

    # Filter with custom patterns
    filtered_urls =
      unique_urls
      |> Enum.filter(fn url ->
        matches_patterns?(url, include_patterns, exclude_patterns, case_sensitive)
      end)

    filtered_count = length(filtered_urls)
    excluded_count = length(unique_urls) - filtered_count

    final_stats = %{
      stats
      | filtered: filtered_count,
        excluded: excluded_count,
        duplicates_removed: duplicates_removed
    }

    {:ok, filtered_urls, final_stats}
  end

  def filter_with_patterns(_, _), do: {:error, :invalid_url_list}

  @doc """
  Normalize URLs for comparison and deduplication.

  Handles:
  - Trailing slashes
  - Query parameters (optional removal)
  - Fragment identifiers
  - Protocol normalization (http → https)

  ## Examples

      iex> normalize_url("https://example.com/page/")
      "https://example.com/page"

      iex> normalize_url("http://example.com/page")
      "https://example.com/page"

      iex> normalize_url("https://example.com/page?ref=homepage", remove_query: true)
      "https://example.com/page"
  """
  def normalize_url(url, options \\ [])

  def normalize_url(url, options) when is_binary(url) do
    remove_query = Keyword.get(options, :remove_query, false)

    url
    |> String.replace(~r{^http://}, "https://")
    |> remove_trailing_slash()
    |> remove_fragment()
    |> maybe_remove_query(remove_query)
  end

  def normalize_url(_, _), do: nil

  @doc """
  Batch normalize URLs.

  ## Examples

      iex> normalize_urls(["https://example.com/page/", "http://example.com/other"])
      ["https://example.com/page", "https://example.com/other"]
  """
  def normalize_urls(urls, options \\ [])

  def normalize_urls(urls, options) when is_list(urls) do
    urls
    |> Enum.map(&normalize_url(&1, options))
    |> Enum.reject(&is_nil/1)
  end

  def normalize_urls(_, _), do: []

  @doc """
  Extract article IDs from a list of URLs.

  Returns a list of {url, article_id} tuples.

  ## Examples

      iex> extract_article_ids(["https://www.sortiraparis.com/articles/123-event"])
      [{"https://www.sortiraparis.com/articles/123-event", "123"}]
  """
  def extract_article_ids(urls) when is_list(urls) do
    urls
    |> Enum.map(fn url ->
      case Config.extract_article_id(url) do
        nil -> nil
        article_id -> {url, article_id}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def extract_article_ids(_), do: []

  # Private functions

  defp matches_patterns?(url, include_patterns, exclude_patterns, case_sensitive) do
    url_compare = if case_sensitive, do: url, else: String.downcase(url)

    has_include =
      Enum.any?(include_patterns, fn pattern ->
        pattern_compare = if case_sensitive, do: pattern, else: String.downcase(pattern)
        String.contains?(url_compare, pattern_compare)
      end)

    has_exclude =
      Enum.any?(exclude_patterns, fn pattern ->
        pattern_compare = if case_sensitive, do: pattern, else: String.downcase(pattern)
        String.contains?(url_compare, pattern_compare)
      end)

    has_include and not has_exclude
  end

  defp remove_trailing_slash(url) do
    String.replace(url, ~r{/$}, "")
  end

  defp remove_fragment(url) do
    case String.split(url, "#", parts: 2) do
      [base_url, _fragment] -> base_url
      [base_url] -> base_url
    end
  end

  defp maybe_remove_query(url, true) do
    case String.split(url, "?", parts: 2) do
      [base_url, _query] -> base_url
      [base_url] -> base_url
    end
  end

  defp maybe_remove_query(url, false), do: url
end
