defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Source do
  @moduledoc """
  Geeks Who Drink source configuration for the unified discovery system.

  US-based trivia company with 700+ weekly trivia nights across the United States.
  Priority 35: Regional specialist source.

  ## Coverage
  - United States (national coverage)
  - 700+ weekly recurring trivia events

  ## Data Characteristics
  - WordPress AJAX API with nonce authentication
  - GPS coordinates provided directly (no geocoding needed)
  - Performer data (quizmaster name and profile image)
  - Weekly recurring events at consistent times
  - All events are free to attend
  """

  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.{
    Config,
    Jobs.SyncJob,
    Jobs.IndexJob,
    Jobs.VenueDetailJob
  }

  def name, do: "Geeks Who Drink"

  def key, do: "geeks-who-drink"

  def enabled?, do: Application.get_env(:eventasaurus, :geeks_who_drink_enabled, false)

  # Priority 35: Same as Question One (regional specialist)
  # Strong US coverage, established brand, reliable data
  def priority, do: 35

  def config do
    %{
      base_url: Config.base_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      timeout: Config.timeout(),
      retry_attempts: Config.max_retries(),
      retry_delay_ms: Config.retry_delay_ms(),

      # Regional settings
      country: "United States",
      timezone: "America/New_York",
      locale: "en_US",

      # Job configuration
      sync_job: SyncJob,
      index_job: IndexJob,
      detail_job: VenueDetailJob,

      # Queue settings
      sync_queue: :scraper_index,
      detail_queue: :scraper_detail,

      # Feature flags
      api_type: :hybrid,
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
         :ok <- validate_job_modules() do
      {:ok, "Geeks Who Drink source configuration valid"}
    end
  end

  defp validate_url_accessibility do
    # Check if base URL is accessible
    case HTTPoison.head(Config.base_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..399 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "Geeks Who Drink website returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Geeks Who Drink website: #{inspect(reason)}"}
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
