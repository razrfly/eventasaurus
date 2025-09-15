defmodule EventasaurusDiscovery.Sources.Bandsintown.Config do
  @moduledoc """
  Configuration for BandsInTown scraper using unified source structure.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @base_url "https://www.bandsintown.com"
  @rate_limit 2  # Conservative rate limit for scraping

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "BandsInTown",
      slug: "bandsintown",
      priority: 80,  # Lower priority than Ticketmaster
      rate_limit: @rate_limit,
      timeout: 15_000,  # Longer timeout for scraping
      max_retries: 3,
      queue: :discovery,
      base_url: @base_url,
      api_key: nil,  # No API key needed for scraping
      api_secret: nil
    })
  end

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