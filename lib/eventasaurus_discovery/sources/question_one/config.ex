defmodule EventasaurusDiscovery.Sources.QuestionOne.Config do
  @moduledoc """
  Runtime configuration for Question One scraper.

  Provides centralized access to environment-specific settings
  for the Question One trivia event source.
  """

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
