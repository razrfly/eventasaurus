defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Config do
  @moduledoc """
  Runtime configuration for Speed Quizzing scraper.

  Provides centralized access to environment-specific settings
  for the Speed Quizzing trivia event source.
  """

  # Speed Quizzing URLs (no authentication required - public HTML scraping)
  def index_url, do: "https://www.speedquizzing.com/find/"

  def event_url_format, do: "https://www.speedquizzing.com/events/{event_id}/"

  def base_url, do: "https://www.speedquizzing.com"

  # Rate limiting: 2 seconds between requests to be respectful
  # (HTML scraping can be more intensive than API calls)
  def rate_limit, do: 2

  # 30 second timeout for HTTP requests (HTML pages can be larger)
  def timeout, do: 30_000

  # Maximum number of retries for failed requests
  def max_retries, do: 3

  # Delay between retries (exponential backoff starting at 500ms)
  def retry_delay_ms, do: 500

  # HTTP headers for requests
  # NOTE: Currently unused - we use empty headers [] like trivia_advisor
  # HTTPoison (Hackney) v2.0 doesn't decompress brotli by default
  def headers do
    [
      {"User-Agent", "Eventasaurus Discovery Bot (https://eventasaurus.com)"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.9"},
      {"Accept-Encoding", "gzip, deflate"}
    ]
  end
end
