defmodule EventasaurusDiscovery.Sources.QuestionOne.Config do
  @moduledoc """
  Runtime configuration for Question One scraper.

  Provides centralized access to environment-specific settings
  for the Question One trivia event source.

  ## Deduplication Strategy

  Uses `:cross_source_fuzzy` - Cross-source fuzzy matching for quiz/trivia events.
  May identify same venues across different quiz providers.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Question One",
      slug: "question_one",
      priority: 50,
      rate_limit: 2,
      timeout: 30_000,
      max_retries: 2,
      queue: :discovery,
      base_url: base_url(),
      api_key: nil,
      api_secret: nil
    })
  end

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def dedup_strategy, do: :cross_source_fuzzy

  def base_url, do: "https://questionone.com"

  def feed_url, do: "#{base_url()}/venues/feed/"

  # Rate limiting: 2 seconds between requests to be respectful
  def rate_limit, do: 2

  # 30 second timeout for HTTP requests
  def timeout, do: 30_000

  # Maximum number of retries for failed requests
  def max_retries, do: 2

  # Delay between retries (5 seconds)
  def retry_delay_ms, do: 5_000

  # HTTP headers for requests
  def headers do
    [
      {"User-Agent", "Eventasaurus Discovery Bot (https://eventasaurus.com)"},
      {"Accept", "application/rss+xml, application/xml, text/xml, */*"}
    ]
  end
end
