defmodule EventasaurusDiscovery.Sources.WeekPl.Config do
  @moduledoc """
  Configuration for week.pl GraphQL API.

  ## API Endpoint
  https://api.week.pl/graphql

  The week.pl platform uses GraphQL for all data access. The Next.js SSR endpoints
  are not suitable for programmatic access as they hardcode region to Warsaw and
  limit results to 3 restaurants.

  ## Deduplication Strategy

  Uses `:cross_source_fuzzy` - Cross-source fuzzy matching for Polish cultural
  events. May overlap with Karnet and other Polish event sources.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Week.pl",
      slug: "week_pl",
      priority: 50,
      rate_limit: 2,
      timeout: 15_000,
      max_retries: 3,
      queue: :discovery,
      base_url: base_url(),
      api_key: nil,
      api_secret: nil
    })
  end

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def dedup_strategy, do: :cross_source_fuzzy

  def base_url, do: "https://week.pl"
  def graphql_url, do: "https://api.week.pl/graphql"

  @doc """
  HTTP headers for GraphQL requests
  """
  def graphql_headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Accept-Language", "pl,en;q=0.9"},
      {"User-Agent", "Mozilla/5.0 (compatible; EventasaurusBot/1.0)"}
    ]
  end

  # Rate limiting
  # 2 seconds between requests
  def request_delay_ms, do: 2_000
  def max_retries, do: 3
  def retry_delay_ms, do: 5_000
  def timeout_ms, do: 15_000
end
