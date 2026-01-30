defmodule EventasaurusDiscovery.Sources.PubquizPl.Source do
  @moduledoc """
  PubQuiz.pl source configuration for the unified discovery system.

  Regional scraper for Poland-wide weekly trivia events.
  Priority 25: Higher than city-specific (Karnet), lower than global APIs.

  ## City Matching Strategy

  PubQuiz does not require a dedicated CityMatcher module because:

  1. **VenueProcessor Auto-Creation**: The VenueProcessor automatically creates
     city records from geocoded addresses when venues are processed. This provides
     definitive coordinates and city identification.

  2. **Unambiguous City Names**: Polish city names from PubQuiz.pl (Warszawa,
     Kraków, Gdańsk, etc.) are unambiguous within Poland and map directly to
     database city records without conflicts.

  3. **Geocoding as Source of Truth**: The geocoding service (Google Maps API)
     provides authoritative city identification based on the full address, which
     is more reliable than string matching on city names.

  A dedicated CityMatcher module would only be needed if:
  - City names were ambiguous (e.g., "Cambridge" existing in multiple countries)
  - Multiple cities with the same name existed in Poland
  - Manual city mapping was required before geocoding
  - Alternative spellings needed to be handled (e.g., "Warszawa" vs "Warsaw")

  Since none of these conditions apply to PubQuiz.pl, the current approach of
  letting VenueProcessor handle city creation through geocoding is optimal.
  """

  alias EventasaurusDiscovery.Sources.PubquizPl.{
    Config,
    Jobs.SyncJob,
    Jobs.VenueDetailJob
  }

  def name, do: "PubQuiz Poland"

  def key, do: "pubquiz-pl"

  def enabled?, do: Application.get_env(:eventasaurus, :pubquiz_enabled, true)

  # Priority 25: Between BandsInTown (20) and Karnet (30)
  # Higher than Karnet: covers all Polish cities vs. single city
  # Lower than global APIs: Poland-only vs. worldwide
  def priority, do: 25

  def config do
    %{
      base_url: Config.base_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      timeout: Config.timeout(),
      retry_attempts: Config.max_retries(),
      retry_delay_ms: Config.retry_delay_ms(),

      # Localized settings
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL",

      # Job configuration
      sync_job: SyncJob,
      detail_job: VenueDetailJob,

      # Queue settings
      sync_queue: :discovery,
      detail_queue: :scraper_detail,

      # Features
      supports_api: false,
      supports_pagination: false,
      supports_date_filtering: false,
      supports_venue_details: true,
      supports_performer_details: false,
      supports_ticket_info: false,
      supports_recurring_events: true
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
      {:ok, "PubQuiz source configuration valid"}
    end
  end

  defp validate_url_accessibility do
    # Check if base URL is accessible
    case HTTPoison.head(Config.base_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..399 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "PubQuiz website returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach PubQuiz website: #{inspect(reason)}"}
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
