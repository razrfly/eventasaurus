defmodule EventasaurusDiscovery.Sources.Inquizition.Config do
  @moduledoc """
  Runtime configuration for Inquizition scraper.

  Provides centralized access to environment-specific settings
  for the Inquizition trivia event source.
  """

  # StoreLocatorWidgets CDN endpoint (public, no authentication required)
  # UID: 7f3962110f31589bc13cdc3b7b85cfd7 (Inquizition's account)
  def cdn_url, do: "https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7"

  # Rate limiting: 2 seconds between requests to be respectful
  # (CDN can handle more, but we're being conservative)
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
      {"Accept", "application/json,text/javascript,*/*;q=0.8"},
      {"Accept-Language", "en-GB,en;q=0.9"}
    ]
  end
end
