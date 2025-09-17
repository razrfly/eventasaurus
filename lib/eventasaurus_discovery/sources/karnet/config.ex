defmodule EventasaurusDiscovery.Sources.Karnet.Config do
  @moduledoc """
  Configuration for Karnet Kraków Culture scraper using unified source structure.

  Scrapes events from https://karnet.krakowculture.pl/ - a comprehensive cultural
  events portal for Kraków, Poland featuring festivals, concerts, performances,
  exhibitions, and outdoor events.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @base_url "https://karnet.krakowculture.pl"
  @rate_limit 4  # Conservative rate limit (4 seconds between requests)
  @timeout 20_000  # Longer timeout for slower site

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Karnet Kraków",
      slug: "karnet",
      priority: 70,  # Lower priority than Ticketmaster and BandsInTown
      rate_limit: @rate_limit,
      timeout: @timeout,
      max_retries: 3,
      queue: :discovery,
      base_url: @base_url,
      api_key: nil,  # No API key needed for HTML scraping
      api_secret: nil,
      metadata: %{
        "language" => "pl",  # Primary language is Polish
        "encoding" => "UTF-8",
        "supports_pagination" => true,
        "supports_filters" => true,
        "event_types" => ["festivals", "concerts", "performances", "exhibitions", "outdoor"]
      }
    })
  end

  def base_url, do: @base_url
  def rate_limit, do: @rate_limit
  def timeout, do: @timeout
  def max_pages, do: Application.get_env(:eventasaurus_discovery, :karnet_max_pages, 10)

  @doc """
  Build URL for events listing page with optional page number.
  Karnet uses query parameters for pagination: ?Item_page=2
  """
  def build_events_url(page \\ 1) do
    if page == 1 do
      "#{@base_url}/wydarzenia/"
    else
      "#{@base_url}/wydarzenia/?Item_page=#{page}"
    end
  end

  @doc """
  Build URL for individual event page.
  Event URLs can be relative or absolute paths.
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