defmodule EventasaurusDiscovery.Sources.Waw4Free.Config do
  @moduledoc """
  Configuration for Waw4Free Warsaw free events scraper.

  Scrapes events from https://waw4free.pl/ - a comprehensive free events
  portal for Warsaw (Warszawa), Poland featuring concerts, workshops,
  exhibitions, theater, sports, and family events.

  All events on this source are FREE.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @base_url "https://waw4free.pl"
  # Conservative rate limit (2 seconds between requests)
  @rate_limit 2
  # Standard timeout
  @timeout 30_000

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Waw4Free",
      slug: "waw4free",
      # Local source priority (similar to Karnet at 70, but slightly lower as it's more niche)
      priority: 35,
      rate_limit: @rate_limit,
      timeout: @timeout,
      max_retries: 2,
      queue: :discovery,
      base_url: @base_url,
      # No API key needed for HTML scraping
      api_key: nil,
      api_secret: nil,
      metadata: %{
        # Primary language is Polish
        "language" => "pl",
        "encoding" => "UTF-8",
        "supports_pagination" => false,
        # Single-page category listings
        "supports_filters" => true,
        # Filter by category and district
        "event_types" => [
          "concerts",
          "workshops",
          "exhibitions",
          "theater",
          "sports",
          "family",
          "festivals"
        ],
        "all_events_free" => true
      }
    })
  end

  def base_url, do: @base_url
  def rate_limit, do: @rate_limit
  def timeout, do: @timeout
  def max_pages, do: Application.get_env(:eventasaurus_discovery, :waw4free_max_pages, 1)

  @doc """
  Categories available on waw4free.pl (in Polish).
  """
  def categories do
    [
      "koncerty",
      # concerts
      "warsztaty",
      # workshops
      "wystawy",
      # exhibitions
      "teatr",
      # theater
      "sport",
      # sports
      "dla-dzieci",
      # for children
      "festiwale",
      # festivals
      "inne"
      # other
    ]
  end

  @doc """
  Build URL for category listing page.
  Format: /warszawa-darmowe-{category}
  Example: /warszawa-darmowe-koncerty
  """
  def build_category_url(category) do
    "#{@base_url}/warszawa-darmowe-#{category}"
  end

  @doc """
  Build URL for individual event page.
  Format: /wydarzenie-{id}-{slug}
  Event URLs should be absolute paths from the website.
  """
  def build_event_url(event_path) do
    cond do
      String.starts_with?(event_path, "http") ->
        event_path

      String.starts_with?(event_path, "/") ->
        "#{@base_url}#{event_path}"

      true ->
        "#{@base_url}/#{event_path}"
    end
  end

  @doc """
  Extract event ID from URL.
  Format: /wydarzenie-{id}-{slug}
  Returns: "waw4free_{id}"
  """
  def extract_external_id(url) do
    case Regex.run(~r/\/wydarzenie-(\d+)-/, url) do
      [_, id] -> "waw4free_#{id}"
      _ -> nil
    end
  end

  @doc """
  Headers for HTTP requests to handle Polish content properly.
  """
  def headers do
    [
      {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "pl,en;q=0.9"},
      {"Accept-Encoding", "gzip, deflate"},
      {"Cache-Control", "no-cache"}
    ]
  end
end
