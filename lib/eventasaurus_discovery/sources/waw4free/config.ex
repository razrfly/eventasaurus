defmodule EventasaurusDiscovery.Sources.Waw4free.Config do
  @moduledoc """
  Configuration for Waw4free Warsaw free events scraper.

  Scrapes events from https://waw4free.pl/ - a comprehensive free events
  portal for Warsaw (Warszawa), Poland featuring concerts, workshops,
  exhibitions, theater, sports, and family events.

  All events on this source are FREE.

  ## Deduplication Strategy

  Uses `:cross_source_fuzzy` - Full cross-source fuzzy matching using
  performer, venue, date, and GPS coordinates. Lower priority source
  that defers to higher-priority sources like Bandsintown.
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
      name: "Waw4free",
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

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def dedup_strategy, do: :cross_source_fuzzy

  def base_url, do: @base_url
  def rate_limit, do: @rate_limit
  def timeout, do: @timeout
  def max_pages, do: Application.get_env(:eventasaurus, :waw4free_max_pages, 1)

  @doc """
  Categories available on waw4free.pl (in Polish).
  Returns list of category slugs used in URLs.
  """
  def categories do
    category_info()
    |> Enum.map(& &1.slug)
  end

  @doc """
  Get full category information including translations.
  Returns list of category maps with slug, name_pl, name_en, and description.
  """
  def category_info do
    [
      %{
        slug: "koncerty",
        name_pl: "Koncerty",
        name_en: "Concerts",
        description: "Music concerts and live performances"
      },
      %{
        slug: "warsztaty",
        name_pl: "Warsztaty",
        name_en: "Workshops",
        description: "Educational workshops and hands-on activities"
      },
      %{
        slug: "wystawy",
        name_pl: "Wystawy",
        name_en: "Exhibitions",
        description: "Art exhibitions and gallery shows"
      },
      %{
        slug: "teatr",
        name_pl: "Teatr",
        name_en: "Theatre",
        description: "Theatre performances and dramatic arts"
      },
      %{
        slug: "sport",
        name_pl: "Sport",
        name_en: "Sports",
        description: "Sports events and activities"
      },
      %{
        slug: "dla-dzieci",
        name_pl: "Dla Dzieci",
        name_en: "For Children",
        description: "Family-friendly and children's events"
      },
      %{
        slug: "festiwale",
        name_pl: "Festiwale",
        name_en: "Festivals",
        description: "Festivals and multi-day events"
      },
      %{
        slug: "inne",
        name_pl: "Inne",
        name_en: "Other",
        description: "Miscellaneous events not fitting other categories"
      }
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
      [_, id] -> "waw4free_event_#{id}"
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
