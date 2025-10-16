defmodule EventasaurusDiscovery.Sources.Quizmeisters.Config do
  @moduledoc """
  Runtime configuration for Quizmeisters scraper.

  Provides centralized access to environment-specific settings
  for the Quizmeisters trivia event source.
  """

  def base_url, do: "https://quizmeisters.com"

  # storerocket.io public API endpoint (no authentication required)
  def api_url, do: "https://storerocket.io/api/user/kDJ3BbK4mn/locations"

  # Rate limiting: 2 seconds between requests to be respectful
  def rate_limit, do: 2

  # 30 second timeout for HTTP requests
  def timeout, do: 30_000

  # Maximum number of retries for failed requests
  def max_retries, do: 3

  # Delay between retries (exponential backoff starting at 500ms)
  def retry_delay_ms, do: 500

  # HTTP headers for requests
  def headers do
    [
      {"User-Agent", "Eventasaurus Discovery Bot (https://eventasaurus.com)"},
      {"Accept", "application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.9"}
    ]
  end
end
