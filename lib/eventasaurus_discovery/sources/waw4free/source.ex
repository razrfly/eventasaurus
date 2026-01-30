defmodule EventasaurusDiscovery.Sources.Waw4free.Source do
  @moduledoc """
  Waw4Free source configuration for the unified discovery system.

  Lower priority, localized scraper for Warsaw (Warszawa) free events.
  All events on this source are FREE events for Warsaw, Poland.
  """

  alias EventasaurusDiscovery.Sources.Waw4free.{
    Config,
    Jobs.SyncJob,
    Jobs.EventDetailJob
  }

  def name, do: "Waw4free"

  def key, do: "waw4free"

  def enabled?, do: Application.get_env(:eventasaurus, :waw4free_enabled, true)

  # Lower priority than Ticketmaster (90), BandsInTown (80), Resident Advisor (75)
  # Similar to Karnet (30) as a local/regional Polish source
  def priority, do: 35

  def config do
    %{
      base_url: Config.base_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      max_pages: Config.max_pages(),
      timeout: 30_000,
      retry_attempts: 2,
      retry_delay_ms: 5_000,

      # Localized settings
      city: "Warszawa",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL",

      # Job configuration
      sync_job: SyncJob,
      detail_job: EventDetailJob,

      # Queue settings
      sync_queue: :scraper_index,
      detail_queue: :scraper_detail,

      # Features
      supports_api: false,
      supports_pagination: false,
      # Single-page listings
      supports_date_filtering: false,
      supports_venue_details: true,
      supports_performer_details: false,
      supports_ticket_info: false,
      # All events are free

      # All events on this source are free
      all_events_free: true
    }
  end

  def sync_job_args(options \\ %{}) do
    %{
      "source" => key(),
      "max_pages" => options[:max_pages] || Config.max_pages(),
      "start_date" => options[:start_date],
      "end_date" => options[:end_date]
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
         :ok <- validate_job_modules() do
      {:ok, "Waw4free source configuration valid"}
    end
  end

  defp validate_url_accessibility do
    # Check if base URL is accessible
    case HTTPoison.head(Config.base_url(), Config.headers(), timeout: 10_000) do
      {:ok, %{status_code: status}} when status in 200..399 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "Waw4free website returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Waw4free website: #{inspect(reason)}"}
    end
  end

  defp validate_job_modules do
    modules = [SyncJob, EventDetailJob]

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
