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

  ## Deduplication Strategy

  Uses `:external_id_only` - Primarily uses external_id (article_id) for
  deduplication within the source. Limited cross-source matching since
  this is a Paris-specific source with unique event identifiers.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @base_url "https://www.sortiraparis.com"
  @sitemap_url "#{@base_url}/sitemap-index.xml"

  # Conservative rate limit (4-5 seconds between requests)
  # Helps avoid bot protection triggers
  @rate_limit 5

  # Longer timeout for slower responses and bot protection delays
  @timeout 10_000

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Sortir à Paris",
      slug: "sortiraparis",
      priority: 60,
      rate_limit: @rate_limit,
      timeout: @timeout,
      max_retries: 3,
      queue: :discovery,
      base_url: @base_url,
      api_key: nil,
      api_secret: nil
    })
  end

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def dedup_strategy, do: :external_id_only

  def base_url, do: @base_url
  def sitemap_url, do: @sitemap_url
  def rate_limit, do: @rate_limit
  def timeout, do: @timeout

  @doc """
  List of sitemap URLs to scrape for bilingual content (English + French).

  ## Language Structure

  - **English sitemaps**: `sitemap-en-{1,2,3,4}.xml` - Contains English article URLs
  - **French sitemaps**: `sitemap-fr-{1,2}.xml` - Contains French article URLs (same events)

  Each article has consistent article_id across both languages:
  - English: `/en/articles/{article_id}-event-title`
  - French: `/articles/{article_id}-event-title` (default, no language prefix)

  ## Returns

  Returns a list of maps with sitemap URL and language metadata:
  ```elixir
  [
    %{url: "https://www.sortiraparis.com/sitemap-en-1.xml", language: "en"},
    %{url: "https://www.sortiraparis.com/sitemap-fr-1.xml", language: "fr"},
    ...
  ]
  ```

  ## Options

  - `language: :en` - Only English sitemaps
  - `language: :fr` - Only French sitemaps
  - `language: :all` - Both languages (default)
  """
  def sitemap_urls(language \\ :all) do
    case language do
      :en ->
        [
          %{url: "#{@base_url}/sitemap-en-1.xml", language: "en"},
          %{url: "#{@base_url}/sitemap-en-2.xml", language: "en"},
          %{url: "#{@base_url}/sitemap-en-3.xml", language: "en"},
          %{url: "#{@base_url}/sitemap-en-4.xml", language: "en"}
        ]

      :fr ->
        [
          %{url: "#{@base_url}/sitemap-fr-1.xml", language: "fr"},
          %{url: "#{@base_url}/sitemap-fr-2.xml", language: "fr"}
        ]

      :all ->
        sitemap_urls(:en) ++ sitemap_urls(:fr)
    end
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

  Works with both English and French URL patterns:
  - English: `/en/articles/319282-title`
  - French: `/articles/319282-title` (no /en/ prefix)

  ## Examples

      iex> extract_article_id("/articles/319282-indochine-concert")
      "319282"

      iex> extract_article_id("/en/articles/319282-indochine-concert")
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
  Detect language from URL pattern.

  ## URL Patterns

  - English: `/en/articles/{id}` or contains `/en/`
  - French: `/articles/{id}` without `/en/` (default language)

  ## Examples

      iex> detect_language("/en/articles/319282-event")
      "en"

      iex> detect_language("/articles/319282-event")
      "fr"

      iex> detect_language("https://www.sortiraparis.com/en/concerts/319282")
      "en"
  """
  def detect_language(url) when is_binary(url) do
    if String.contains?(url, "/en/") do
      "en"
    else
      "fr"
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

  Works with both English and French URLs by checking for article ID pattern.

  ## Detection Strategy

  Event articles have the pattern `/articles/{digit}-{slug}` which is consistent
  across both English and French versions. This is more reliable than category
  keywords which differ between languages:
  - English: `/en/what-to-see-in-paris/shows/articles/123-event`
  - French: `/scenes/spectacle/articles/123-event`

  We exclude guide pages, news, and listicles which don't represent specific events.

  ## Examples

      iex> is_event_url?("https://www.sortiraparis.com/en/what-to-see-in-paris/shows/articles/319282-event")
      true

      iex> is_event_url?("https://www.sortiraparis.com/scenes/spectacle/articles/319282-event")
      true

      iex> is_event_url?("https://www.sortiraparis.com/en/news/guides/53380-what-to-do-this-week")
      false

      iex> is_event_url?("https://www.sortiraparis.com")
      false
  """
  def is_event_url?(url) when is_binary(url) do
    # Check if URL has article ID pattern: /articles/{digits}-
    has_article_pattern = Regex.match?(~r{/articles/\d+-}, url)

    # Exclude non-event content patterns
    has_exclude_pattern = Enum.any?(exclude_patterns(), &String.contains?(url, &1))

    has_article_pattern and not has_exclude_pattern
  end
end
