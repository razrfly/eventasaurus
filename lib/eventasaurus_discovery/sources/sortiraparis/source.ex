defmodule EventasaurusDiscovery.Sources.Sortiraparis.Source do
  @moduledoc """
  Sortiraparis source configuration for the unified discovery system.

  Regional reliable source for Paris cultural events. Comprehensive coverage
  of concerts, exhibitions, theater, and cultural activities across Paris.

  **Priority**: 65 (Regional reliable source)
  **Coverage**: Paris, France
  **Languages**: 30+ (using English for consistency)
  **Update Frequency**: Daily via sitemap
  """

  alias EventasaurusDiscovery.Sources.Sortiraparis.{
    Config,
    Jobs.SyncJob
    # Jobs.EventDetailJob  # TODO: Implement in Phase 4
  }

  def name, do: "Sortiraparis"

  def key, do: "sortiraparis"

  def enabled?, do: Application.get_env(:eventasaurus_discovery, :sortiraparis_enabled, true)

  # Regional reliable source - priority 65
  # Below international sources (Ticketmaster 90, Resident Advisor 75, Bandsintown 80)
  # Above local sources (Karnet 30, Cinema sources 50)
  def priority, do: 65

  def config do
    %{
      base_url: Config.base_url(),
      sitemap_url: Config.sitemap_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      timeout: Config.timeout(),
      retry_attempts: 2,
      retry_delay_ms: 5_000,

      # Localized settings
      city: "Paris",
      country: "France",
      timezone: "Europe/Paris",
      locale: "en_US",

      # Job configuration
      sync_job: SyncJob,
      detail_job: nil,  # TODO: Add EventDetailJob in Phase 4

      # Queue settings
      sync_queue: :scraper_index,
      detail_queue: :scraper_detail,

      # Bot protection handling
      requires_playwright_fallback: true,
      browser_like_headers: true,

      # Features
      supports_api: false,
      supports_pagination: false,  # Uses sitemap discovery
      supports_date_filtering: false,
      supports_venue_details: true,
      supports_performer_details: true,
      supports_ticket_info: true,

      # Geocoding strategy
      requires_geocoding: true,
      geocoding_strategy: :multi_provider,  # Uses AddressGeocoder orchestrator

      # Data quality indicators
      has_coordinates: false,  # Must geocode all venues
      has_ticket_urls: true,
      has_performer_info: true,
      has_images: true,
      has_descriptions: true,

      # Scraper-specific settings
      event_categories: [
        "concerts-music-festival",
        "exhibit-museum",
        "shows",
        "theater"
      ],
      exclude_patterns: [
        "guides",
        "/news/",
        "where-to-eat"
      ]
    }
  end

  def sync_job_args(options \\ %{}) do
    %{
      "source" => key(),
      "sitemap_urls" => options[:sitemap_urls] || Config.sitemap_urls(),
      "limit" => options[:limit]
    }
  end

  def detail_job_args(event_url, metadata \\ %{}) do
    %{
      "source" => key(),
      "url" => event_url,
      "event_metadata" => metadata
    }
  end

  def validate_config do
    with :ok <- validate_url_accessibility(),
         :ok <- validate_sitemap_accessibility(),
         :ok <- validate_job_modules() do
      {:ok, "Sortiraparis source configuration valid"}
    end
  end

  defp validate_url_accessibility do
    # Check if base URL is accessible
    case HTTPoison.head(Config.base_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..399 ->
        :ok

      {:ok, %{status_code: 401}} ->
        # 401 is expected sometimes due to bot protection - not a config error
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "Sortiraparis website returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Sortiraparis website: #{inspect(reason)}"}
    end
  end

  defp validate_sitemap_accessibility do
    # Check if sitemap is accessible
    case HTTPoison.head(Config.sitemap_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..399 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "Sortiraparis sitemap returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Sortiraparis sitemap: #{inspect(reason)}"}
    end
  end

  defp validate_job_modules do
    modules = [SyncJob]  # TODO: Add EventDetailJob when implemented

    missing =
      Enum.filter(modules, fn module ->
        not Code.ensure_loaded?(module)
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "Missing job modules: #{inspect(missing)}"}
    end
  end
end
