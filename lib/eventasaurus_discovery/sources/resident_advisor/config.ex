defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Config do
  @moduledoc """
  Configuration for Resident Advisor scraper using GraphQL API.

  Resident Advisor (ra.co) is a major international electronic music events platform.
  Uses GraphQL API for data fetching with Google Places geocoding for venue coordinates.

  ## Deduplication Strategy

  Uses `:cross_source_fuzzy` - Full cross-source fuzzy matching for electronic
  music events. High-priority international source that other regional sources
  may defer to for club/DJ events.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @graphql_endpoint "https://ra.co/graphql"
  @base_url "https://ra.co"
  # Conservative rate limit - 2 requests per second
  @rate_limit 2
  # Longer timeout for GraphQL queries
  @timeout 15_000

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Resident Advisor",
      slug: "resident_advisor",
      # Priority: Below Ticketmaster (90) and Bandsintown (80), above regional sources
      priority: 75,
      rate_limit: @rate_limit,
      timeout: @timeout,
      max_retries: 3,
      queue: :discovery,
      base_url: @base_url,
      # No API key required - public GraphQL endpoint
      api_key: nil,
      api_secret: nil,
      metadata: %{
        graphql_endpoint: @graphql_endpoint,
        requires_auth: false,
        venue_geocoding_strategy: :google_places,
        focus: "electronic_music",
        coverage: "international"
      }
    })
  end

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def dedup_strategy, do: :cross_source_fuzzy

  @doc """
  GraphQL endpoint URL for Resident Advisor API.
  """
  def graphql_endpoint, do: @graphql_endpoint

  @doc """
  Base URL for constructing event and venue URLs.
  """
  def base_url, do: @base_url

  @doc """
  Rate limit in requests per second.
  """
  def rate_limit, do: @rate_limit

  @doc """
  Request timeout in milliseconds.
  """
  def timeout, do: @timeout

  @doc """
  Build full event URL from content path.

  ## Examples

      iex> build_event_url("/events/1234567-event-slug")
      "https://ra.co/events/1234567-event-slug"
  """
  def build_event_url(content_url) when is_binary(content_url) do
    if String.starts_with?(content_url, "http") do
      content_url
    else
      "#{@base_url}#{content_url}"
    end
  end

  def build_event_url(_), do: nil

  @doc """
  Build full venue URL from content path.

  ## Examples

      iex> build_venue_url("/clubs/12345-venue-slug")
      "https://ra.co/clubs/12345-venue-slug"
  """
  def build_venue_url(content_url) when is_binary(content_url) do
    if String.starts_with?(content_url, "http") do
      content_url
    else
      "#{@base_url}#{content_url}"
    end
  end

  def build_venue_url(_), do: nil
end
