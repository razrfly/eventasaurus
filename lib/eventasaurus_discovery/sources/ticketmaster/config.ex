defmodule EventasaurusDiscovery.Sources.Ticketmaster.Config do
  @moduledoc """
  Configuration for Ticketmaster Discovery API using unified source structure.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @base_url "https://app.ticketmaster.com/discovery/v2"
  @default_radius 50
  @default_page_size 100

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Ticketmaster Discovery API",
      slug: "ticketmaster",
      priority: 100,  # Highest priority - authoritative source
      rate_limit: 5,   # requests per second
      timeout: 10_000,
      max_retries: 3,
      queue: :discovery,
      base_url: @base_url,
      api_key: api_key(),
      api_secret: api_secret()
    })
  end

  def base_url, do: @base_url
  def default_radius, do: @default_radius
  def default_page_size, do: @default_page_size

  def api_key do
    System.get_env("TICKETMASTER_CONSUMER_KEY") ||
      Application.get_env(:eventasaurus, :ticketmaster)[:api_key]
  end

  def api_secret do
    System.get_env("TICKETMASTER_CONSUMER_SECRET") ||
      Application.get_env(:eventasaurus, :ticketmaster)[:api_secret]
  end

  def build_url(endpoint) do
    "#{@base_url}#{endpoint}"
  end

  def default_params do
    %{
      apikey: api_key(),
      size: @default_page_size,
      sort: "date,asc",
      includeTest: "no",
      # Include embedded resources for complete event data
      includeLicensedContent: "yes"
    }
  end
end