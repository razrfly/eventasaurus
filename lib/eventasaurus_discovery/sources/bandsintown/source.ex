defmodule EventasaurusDiscovery.Sources.Bandsintown.Source do
  @moduledoc """
  Source configuration and metadata for Bandsintown event scraper.

  Bandsintown is an international concert discovery platform focused on live music events.
  Provides comprehensive event data with GPS coordinates via JSON-LD structured data.

  ## Priority
  80 - International trusted source with good coverage of music events

  ## Capabilities
  - City-based event discovery
  - GPS coordinates via JSON-LD
  - Comprehensive artist/performer data
  - Pagination API for complete coverage

  ## Limitations
  - Requires JavaScript rendering for initial city pages (via Playwright)
  - Rate limiting recommended (2-3s between requests)
  - Some events may have placeholder images
  """

  alias EventasaurusDiscovery.Sources.Bandsintown.{Client, Config, Transformer}
  alias EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob

  def name, do: "bandsintown"

  def display_name, do: "Bandsintown"

  def priority, do: 80

  def enabled?, do: true

  def requires_api_key?, do: false

  def base_url, do: Config.base_url()

  def sync_job, do: SyncJob

  def transformer, do: Transformer

  def client, do: Client

  def supports_city?(_city), do: true

  def rate_limit_ms, do: 2000

  def metadata do
    %{
      type: :scraper,
      requires_playwright: true,
      provides_gps: true,
      provides_performers: true,
      provides_tickets: true,
      event_types: [:music, :concert],
      coverage: :international,
      update_frequency: :daily
    }
  end
end
