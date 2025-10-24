defmodule EventasaurusDiscovery.Sources.Inquizition.Source do
  @moduledoc """
  Inquizition source configuration for the unified discovery system.

  UK-based trivia company with weekly quiz nights at pubs and venues.
  Priority 35: Regional specialist source.

  ## Coverage
  - United Kingdom (national coverage - single country)
  - Weekly recurring trivia events

  ## Data Characteristics
  - StoreLocatorWidgets CDN endpoint (no authentication required)
  - GPS coordinates provided directly (no geocoding needed)
  - No performer data available
  - No event images available
  - Weekly recurring events at consistent times
  - Standard £2.50 entry fee for all events

  ## Data Source
  - CDN: https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7
  - Format: JSONP (JSON with slw() callback wrapper)
  - Single-stage scraper (no detail pages needed)
  """

  alias EventasaurusDiscovery.Sources.Inquizition.{
    Config,
    Jobs.SyncJob,
    Jobs.IndexJob
  }

  def name, do: "Inquizition"

  def key, do: "inquizition"

  def enabled?, do: Application.get_env(:eventasaurus, :inquizition_enabled, false)

  # Priority 35: Regional specialist (single country coverage)
  # Strong UK coverage, established brand, reliable data
  def priority, do: 35

  def config do
    %{
      cdn_url: Config.cdn_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      timeout: Config.timeout(),
      retry_attempts: Config.max_retries(),
      retry_delay_ms: Config.retry_delay_ms(),

      # Regional settings (covers United Kingdom only)
      countries: ["United Kingdom"],
      timezone: "Europe/London",
      locale: "en_GB",
      currency: "GBP",

      # Job configuration (no detail job - single-stage scraper)
      sync_job: SyncJob,
      index_job: IndexJob,
      detail_job: nil,

      # Queue settings
      sync_queue: :scraper_index,
      detail_queue: nil,

      # Feature flags
      api_type: :cdn,
      supports_api: true,
      supports_pagination: false,
      supports_date_filtering: false,
      supports_venue_details: false,
      supports_performer_details: false,
      supports_ticket_info: true,
      supports_recurring_events: true,

      # Geocoding strategy
      requires_geocoding: false,
      geocoding_strategy: :provided,

      # Data quality indicators
      has_coordinates: true,
      has_ticket_urls: false,
      has_performer_info: false,
      has_images: false,
      has_descriptions: true,

      # Pricing information
      standard_price: 2.50,
      price_currency: "GBP"
    }
  end

  def sync_job_args(options \\ %{}) do
    %{
      "source" => key(),
      "limit" => options[:limit]
    }
  end

  # No detail job for Inquizition (single-stage scraper)
  def detail_job_args(_venue_data, _metadata \\ %{}), do: nil

  def validate_config do
    with :ok <- validate_cdn_accessibility(),
         :ok <- validate_job_modules() do
      {:ok, "Inquizition source configuration valid"}
    end
  end

  defp validate_cdn_accessibility do
    # Check if StoreLocatorWidgets CDN is accessible
    case HTTPoison.get(Config.cdn_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) and body != "" ->
        # Verify JSONP format (allow trailing semicolon: slw(...) or slw(...);)
        trimmed = String.trim(body)

        if String.starts_with?(trimmed, "slw(") and Regex.match?(~r/\)\s*;?\s*$/, trimmed) do
          :ok
        else
          {:error, "CDN response is not valid JSONP format"}
        end

      {:ok, %{status_code: status}} ->
        {:error, "StoreLocatorWidgets CDN returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach StoreLocatorWidgets CDN: #{inspect(reason)}"}
    end
  end

  defp validate_job_modules do
    modules = [SyncJob, IndexJob]

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
