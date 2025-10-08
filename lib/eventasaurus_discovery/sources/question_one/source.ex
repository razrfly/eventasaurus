defmodule EventasaurusDiscovery.Sources.QuestionOne.Source do
  @moduledoc """
  Question One source configuration for the unified discovery system.

  International trivia source covering UK, Ireland, and select international venues.
  Priority 35: Regional specialist source.

  ## Coverage
  - United Kingdom (primary)
  - Ireland
  - Select international venues

  ## Data Characteristics
  - Weekly recurring trivia events
  - RSS feed with pagination
  - Detail pages with icon-based extraction
  - No GPS coordinates (VenueProcessor geocodes)
  """

  alias EventasaurusDiscovery.Sources.QuestionOne.{
    Config,
    Jobs.SyncJob,
    Jobs.VenueDetailJob
  }

  def name, do: "Question One"

  def key, do: "question-one"

  def enabled?, do: Application.get_env(:eventasaurus, :question_one_enabled, true)

  # Priority 35: Between PubQuiz (25) and Karnet (30)
  # Higher than PubQuiz: More established, broader coverage
  # Lower than Karnet: Regional vs city-specific data quality
  def priority, do: 35

  def config do
    %{
      base_url: Config.base_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      timeout: Config.timeout(),
      retry_attempts: Config.max_retries(),
      retry_delay_ms: Config.retry_delay_ms(),

      # Regional settings
      country: "United Kingdom",
      timezone: "Europe/London",
      locale: "en_GB",

      # Job configuration
      sync_job: SyncJob,
      detail_job: VenueDetailJob,

      # Queue settings
      sync_queue: :discovery,
      detail_queue: :scraper_detail,

      # Feature flags
      supports_api: false,
      supports_pagination: true,
      supports_date_filtering: false,
      supports_venue_details: true,
      supports_performer_details: false,
      supports_ticket_info: false,
      supports_recurring_events: true,

      # Geocoding strategy
      requires_geocoding: true,
      geocoding_strategy: :google_places,

      # Data quality indicators
      has_coordinates: false,
      has_ticket_urls: false,
      has_performer_info: false,
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

  def detail_job_args(venue_url, metadata \\ %{}) do
    %{
      "source" => key(),
      "url" => venue_url,
      "venue_metadata" => metadata
    }
  end

  def validate_config do
    with :ok <- validate_url_accessibility(),
         :ok <- validate_job_modules() do
      {:ok, "Question One source configuration valid"}
    end
  end

  defp validate_url_accessibility do
    # Check if base URL is accessible
    case HTTPoison.head(Config.base_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..399 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "Question One website returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Question One website: #{inspect(reason)}"}
    end
  end

  defp validate_job_modules do
    modules = [SyncJob, VenueDetailJob]

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
