defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Source do
  @moduledoc """
  Speed Quizzing source configuration for the unified discovery system.

  International trivia company with smartphone-based interactive quiz platform.
  Priority 35: Regional specialist source (multi-country coverage).

  ## Coverage
  - International: United Kingdom, United States, UAE, and other English-speaking markets
  - Weekly recurring trivia events
  - Active venues in major cities globally

  ## Data Characteristics
  - HTML scraping with embedded JSON (no API authentication required)
  - Two-stage scraping: index page → detail pages
  - GPS coordinates provided directly (no geocoding needed)
  - Performer/host data with profile images available
  - Event descriptions and fee information
  - Weekly recurring events at consistent times

  ## Data Source
  - Index: https://www.speedquizzing.com/find/
  - Format: Embedded JSON in HTML (`var events = JSON.parse('...')`)
  - Detail: https://www.speedquizzing.com/events/{event_id}/
  - Two-stage scraper (index + detail pages)

  ## Migration Note
  This scraper is migrated from the trivia_advisor project.
  Reference: /Users/holdenthomas/Code/paid-projects-2024/trivia_advisor/lib/trivia_advisor/scraping/scrapers/speed_quizzing/
  """

  alias EventasaurusDiscovery.Sources.SpeedQuizzing.{
    Config,
    Jobs.SyncJob,
    Jobs.IndexJob,
    Jobs.DetailJob
  }

  def name, do: "Speed Quizzing"

  def key, do: "speed-quizzing"

  def enabled?, do: Application.get_env(:eventasaurus, :speed_quizzing_enabled, false)

  # Priority 35: Regional specialist (multi-country coverage)
  # Strong international presence, performer data, proven implementation
  def priority, do: 35

  def config do
    %{
      index_url: Config.index_url(),
      event_url_format: Config.event_url_format(),
      rate_limit_ms: Config.rate_limit() * 1000,
      timeout: Config.timeout(),
      retry_attempts: Config.max_retries(),
      retry_delay_ms: Config.retry_delay_ms(),

      # Regional settings (multi-country coverage)
      countries: ["United Kingdom", "United States", "United Arab Emirates"],
      # Default timezone for events (will be overridden by venue location)
      timezone: "Europe/London",
      locale: "en",

      # Job configuration (two-stage scraper: sync + index + detail)
      sync_job: SyncJob,
      index_job: IndexJob,
      detail_job: DetailJob,

      # Queue settings
      sync_queue: :scraper_index,
      detail_queue: :scraper_detail,

      # Feature flags
      api_type: :html,
      supports_api: false,
      supports_pagination: false,
      supports_date_filtering: false,
      supports_venue_details: true,
      supports_performer_details: true,
      supports_ticket_info: true,
      supports_recurring_events: true,

      # Geocoding strategy
      requires_geocoding: false,
      geocoding_strategy: :provided,

      # Data quality indicators
      has_coordinates: true,
      has_ticket_urls: false,
      has_performer_info: true,
      has_images: false,
      has_descriptions: true,

      # Pricing information (varies by venue)
      standard_price: nil,
      price_currency: nil
    }
  end

  def sync_job_args(options \\ %{}) do
    %{
      "source" => key(),
      "limit" => options[:limit],
      "force_update" => options[:force_update] || false
    }
  end

  def detail_job_args(event_data, metadata \\ %{}) do
    %{
      "event_id" =>
        event_data["event_id"] || event_data[:event_id] ||
        event_data["id"] || event_data[:id],
      "source_id" => metadata[:source_id],
      "lat" => event_data["lat"] || event_data[:lat],
      "lng" => event_data["lon"] || event_data["lng"] || event_data[:lng],
      "day_of_week" => event_data["day_of_week"] || event_data[:day_of_week],
      "start_time" => event_data["start_time"] || event_data[:start_time],
      "fee" => event_data["fee"] || event_data[:fee],
      "force_update" => metadata[:force_update] || false
    }
  end

  def validate_config do
    with :ok <- validate_index_accessibility(),
         :ok <- validate_job_modules() do
      {:ok, "Speed Quizzing source configuration valid"}
    end
  end

  defp validate_index_accessibility do
    # Check if index page is accessible
    case HTTPoison.get(Config.index_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: 200, body: body}} when is_binary(body) and body != "" ->
        # Verify embedded JSON pattern exists
        if String.contains?(body, "var events = JSON.parse(") do
          :ok
        else
          {:error, "Index page does not contain expected JSON pattern"}
        end

      {:ok, %{status_code: status}} ->
        {:error, "Speed Quizzing index page returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Speed Quizzing index page: #{inspect(reason)}"}
    end
  end

  defp validate_job_modules do
    modules = [SyncJob, IndexJob, DetailJob]

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
