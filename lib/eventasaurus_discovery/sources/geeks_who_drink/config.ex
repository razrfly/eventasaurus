defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Config do
  @moduledoc """
  Runtime configuration for Geeks Who Drink scraper.

  Provides centralized access to environment-specific settings
  for the Geeks Who Drink trivia event source.
  """

  def base_url, do: "https://www.geekswhodrink.com"

  def venues_url, do: "#{base_url()}/venues/"

  def ajax_url, do: "#{base_url()}/wp-admin/admin-ajax.php"

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
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.9"}
    ]
  end

  # US bounds for map API (covers entire continental US + Alaska + Hawaii)
  def us_bounds do
    %{
      "northLat" => "71.35817123219137",
      "southLat" => "-2.63233642366575",
      "westLong" => "-174.787181",
      "eastLong" => "-32.75593100000001"
    }
  end

  # Map center point (approximate US center)
  def map_center do
    %{
      "startLat" => "44.967243",
      "startLong" => "-103.771556"
    }
  end
end
