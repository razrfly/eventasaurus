defmodule EventasaurusDiscovery.Sources.Bandsintown.Config do
  @moduledoc """
  Configuration for BandsInTown scraper using unified source structure.

  ## Deduplication Strategy

  Uses `:cross_source_fuzzy` - Full cross-source fuzzy matching using
  performer, venue, date, and GPS coordinates. High-priority source
  that other sources defer to for music events.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @base_url "https://www.bandsintown.com"
  # Conservative rate limit for scraping
  @rate_limit 2

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "BandsInTown",
      slug: "bandsintown",
      # Lower priority than Ticketmaster
      priority: 80,
      rate_limit: @rate_limit,
      # Longer timeout for scraping
      timeout: 15_000,
      max_retries: 3,
      queue: :discovery,
      base_url: @base_url,
      # No API key needed for scraping
      api_key: nil,
      api_secret: nil
    })
  end

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def dedup_strategy, do: :cross_source_fuzzy

  def base_url, do: @base_url
  def rate_limit, do: @rate_limit

  def build_city_url(city_slug) do
    "#{@base_url}/choose-dates/mv/1001308/#{city_slug}"
  end

  def build_event_url(event_path) do
    if String.starts_with?(event_path, "http") do
      event_path
    else
      "#{@base_url}#{event_path}"
    end
  end
end
