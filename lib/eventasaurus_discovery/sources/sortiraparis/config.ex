defmodule EventasaurusDiscovery.Sources.Sortiraparis.Config do
  @moduledoc """
  Configuration for Sortiraparis.com scraper using unified source structure.

  Scrapes events from https://www.sortiraparis.com/ - a comprehensive Paris
  cultural events portal featuring concerts, exhibitions, theater, shows,
  and cultural activities. Available in 30+ languages, using English for consistency.

  ## Bot Protection

  Sortiraparis implements inconsistent bot protection (~30% 401 error rate).
  Mitigation strategies:
  - Browser-like headers (reduces 401 rate to ~70% success)
  - Conservative rate limiting (4-5s between requests)
  - Playwright fallback for persistent 401 errors (Phase 3+)

  ## Sitemap Discovery

  Uses sitemap-based discovery instead of pagination:
  - Sitemap index: https://www.sortiraparis.com/sitemap-index.xml
  - English sitemaps: sitemap-en-1.xml through sitemap-en-4.xml
  - Daily updates with new and modified events
  """

  @base_url "https://www.sortiraparis.com"
  @sitemap_url "#{@base_url}/sitemap-index.xml"

  # Conservative rate limit (4-5 seconds between requests)
  # Helps avoid bot protection triggers
  @rate_limit 5

  # Longer timeout for slower responses and bot protection delays
  @timeout 10_000

  def base_url, do: @base_url
  def sitemap_url, do: @sitemap_url
  def rate_limit, do: @rate_limit
  def timeout, do: @timeout

  @doc """
  List of English sitemap URLs to scrape.

  Using English sitemaps for consistency and easier parsing.
  French sitemaps (sitemap-fr-*.xml) contain same events but in French.
  """
  def sitemap_urls do
    [
      "#{@base_url}/sitemap-en-1.xml",
      "#{@base_url}/sitemap-en-2.xml",
      "#{@base_url}/sitemap-en-3.xml",
      "#{@base_url}/sitemap-en-4.xml"
    ]
  end

  @doc """
  Build full URL from relative or absolute path.

  ## Examples

      iex> build_url("/articles/123-event-title")
      "https://www.sortiraparis.com/articles/123-event-title"

      iex> build_url("https://www.sortiraparis.com/articles/123-event-title")
      "https://www.sortiraparis.com/articles/123-event-title"
  """
  def build_url(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "http") ->
        path

      String.starts_with?(path, "/") ->
        "#{@base_url}#{path}"

      true ->
        "#{@base_url}/#{path}"
    end
  end

  @doc """
  Extract article ID from URL.

  ## Examples

      iex> extract_article_id("/articles/319282-indochine-concert")
      "319282"

      iex> extract_article_id("https://www.sortiraparis.com/articles/319282-indochine-concert")
      "319282"
  """
  def extract_article_id(url) when is_binary(url) do
    case Regex.run(~r{/articles/(\d+)-}, url) do
      [_, id] -> id
      _ -> nil
    end
  end

  @doc """
  Generate external_id for an event.

  Format: `sortiraparis_{article_id}`

  For multi-date events, append date suffix in transformer:
  `sortiraparis_{article_id}_{date}` (e.g., "sortiraparis_319282_2026-02-25")

  ## Examples

      iex> generate_external_id("319282")
      "sortiraparis_319282"
  """
  def generate_external_id(article_id) when is_binary(article_id) do
    "sortiraparis_#{article_id}"
  end

  @doc """
  Browser-like HTTP headers to reduce bot protection triggers.

  Based on POC findings, these headers improve success rate to ~70%.
  Playwright fallback needed for remaining 30% 401 errors.
  """
  def headers do
    [
      {"User-Agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.9,fr;q=0.8"},
      {"Accept-Encoding", "gzip, deflate, br"},
      {"Referer", @base_url},
      {"Cache-Control", "no-cache"},
      {"DNT", "1"},
      # Helps avoid bot detection
      {"Upgrade-Insecure-Requests", "1"}
    ]
  end

  @doc """
  Event category URL patterns to include.

  These URL segments indicate event articles (not general content).
  """
  def event_categories do
    [
      "concerts-music-festival",
      "exhibit-museum",
      "shows",
      "theater"
    ]
  end

  @doc """
  URL patterns to exclude (non-event content).

  These patterns indicate guides, reviews, listicles - not specific events.
  """
  def exclude_patterns do
    [
      "guides",
      "/news/",
      "where-to-eat",
      "what-to-do",
      "best-of",
      "top-"
    ]
  end

  @doc """
  Check if URL is likely an event page.

  Uses URL pattern matching based on POC findings.
  Accuracy: ~90%+ (refined during implementation)

  ## Examples

      iex> is_event_url?("https://www.sortiraparis.com/concerts-music-festival/articles/319282-indochine-concert")
      true

      iex> is_event_url?("https://www.sortiraparis.com/guides/best-restaurants-paris")
      false
  """
  def is_event_url?(url) when is_binary(url) do
    has_event_category = Enum.any?(event_categories(), &String.contains?(url, &1))
    has_exclude_pattern = Enum.any?(exclude_patterns(), &String.contains?(url, &1))

    has_event_category and not has_exclude_pattern
  end
end
