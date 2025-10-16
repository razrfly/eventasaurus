defmodule EventasaurusDiscovery.Sources.Quizmeisters.Source do
  @moduledoc """
  Quizmeisters source configuration for the unified discovery system.

  Trivia company with weekly trivia nights across Australia.
  Priority 35: Regional specialist source.

  ## Coverage
  - Australia (national coverage - single country)
  - Weekly recurring trivia events

  ## Data Characteristics
  - storerocket.io public API (no authentication required)
  - GPS coordinates provided directly (no geocoding needed)
  - Performer data (quizmaster name and profile image URLs)
  - Weekly recurring events at consistent times
  - All events are free to attend

  ## Data Source
  - API: https://storerocket.io/api/user/kDJ3BbK4mn/locations
  - Detail pages: https://quizmeisters.com/venues/{venue-slug}
  """

  alias EventasaurusDiscovery.Sources.Quizmeisters.{
    Config,
    Jobs.SyncJob,
    Jobs.IndexJob,
    Jobs.VenueDetailJob
  }

  def name, do: "Quizmeisters"

  def key, do: "quizmeisters"

  def enabled?, do: Application.get_env(:eventasaurus, :quizmeisters_enabled, false)

  # Priority 35: Regional specialist (single country coverage)
  # Strong Australia coverage, established brand, reliable data
  def priority, do: 35

  def config do
    %{
      base_url: Config.base_url(),
      api_url: Config.api_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      timeout: Config.timeout(),
      retry_attempts: Config.max_retries(),
      retry_delay_ms: Config.retry_delay_ms(),

      # Regional settings (covers Australia only)
      countries: ["Australia"],
      timezone: "Australia/Sydney",
      locale: "en_AU",

      # Job configuration
      sync_job: SyncJob,
      index_job: IndexJob,
      detail_job: VenueDetailJob,

      # Queue settings
      sync_queue: :scraper_index,
      detail_queue: :scraper_detail,

      # Feature flags
      api_type: :rest,
      supports_api: true,
      supports_pagination: false,
      supports_date_filtering: false,
      supports_venue_details: true,
      supports_performer_details: true,
      supports_ticket_info: false,
      supports_recurring_events: true,

      # Geocoding strategy
      requires_geocoding: false,
      geocoding_strategy: :provided,

      # Data quality indicators
      has_coordinates: true,
      has_ticket_urls: false,
      has_performer_info: true,
      has_images: true,
      has_descriptions: true
    }
  end

  def sync_job_args(options \\ %{}) do
    %{
      "source" => key(),
      "limit" => options[:limit]
    }
  end

  def detail_job_args(venue_data, metadata \\ %{}) do
    %{
      "source" => key(),
      "venue" => venue_data,
      "venue_metadata" => metadata
    }
  end

  def validate_config do
    with :ok <- validate_url_accessibility(),
         :ok <- validate_api_accessibility(),
         :ok <- validate_job_modules() do
      {:ok, "Quizmeisters source configuration valid"}
    end
  end

  defp validate_url_accessibility do
    # Check if base URL is accessible
    case HTTPoison.head(Config.base_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..399 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "Quizmeisters website returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Quizmeisters website: #{inspect(reason)}"}
    end
  end

  defp validate_api_accessibility do
    # Check if storerocket.io API is accessible
    case HTTPoison.get(Config.api_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "storerocket.io API returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach storerocket.io API: #{inspect(reason)}"}
    end
  end

  defp validate_job_modules do
    modules = [SyncJob, IndexJob, VenueDetailJob]

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
