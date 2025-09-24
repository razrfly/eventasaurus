defmodule EventasaurusDiscovery.Apis.Ticketmaster.Config do
  @moduledoc """
  Configuration for Ticketmaster Discovery API.
  """

  @base_url "https://app.ticketmaster.com/discovery/v2"
  @default_radius 50
  @default_page_size 100
  # requests per second
  @rate_limit 5
  @timeout 10_000
  @max_retries 3

  def api_config do
    %{
      name: "Ticketmaster Discovery API",
      slug: "ticketmaster",
      # Highest priority - authoritative source
      priority: 100,
      base_url: @base_url,
      api_key: api_key(),
      api_secret: api_secret(),
      rate_limit: @rate_limit,
      timeout: @timeout
    }
  end

  def base_url, do: @base_url
  def default_radius, do: @default_radius
  def default_page_size, do: @default_page_size
  def rate_limit, do: @rate_limit
  def timeout, do: @timeout
  def max_retries, do: @max_retries

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
      sort: "date,asc"
    }
  end
end
