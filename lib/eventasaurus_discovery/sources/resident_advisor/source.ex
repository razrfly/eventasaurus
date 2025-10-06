defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Source do
  @moduledoc """
  Resident Advisor source configuration for the unified discovery system.

  High-priority international scraper for electronic music events worldwide.
  Uses GraphQL API for reliable data extraction.
  """

  alias EventasaurusDiscovery.Sources.ResidentAdvisor.{
    Config,
    Jobs.SyncJob,
    Jobs.EventDetailJob
  }

  def name, do: "Resident Advisor"

  def key, do: "resident_advisor"

  def enabled?, do: Application.get_env(:eventasaurus_discovery, :resident_advisor_enabled, true)

  # Priority: Below Ticketmaster (90) and Bandsintown (80), above regional sources (60)
  # RA is a trusted international source for electronic music events
  def priority, do: 75

  def config do
    %{
      graphql_endpoint: Config.graphql_endpoint(),
      base_url: Config.base_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      timeout: Config.timeout(),
      retry_attempts: 2,
      retry_delay_ms: 5_000,

      # API characteristics
      api_type: :graphql,
      requires_auth: false,

      # Job configuration
      sync_job: SyncJob,
      detail_job: EventDetailJob,

      # Queue settings
      sync_queue: :scraper_index,
      detail_queue: :scraper_detail,

      # Features
      supports_api: true,
      supports_pagination: true,
      supports_date_filtering: true,
      supports_venue_details: false,
      # RA venue query experimental
      supports_performer_details: false,
      # Limited in listing
      supports_ticket_info: true,

      # Geocoding
      requires_geocoding: true,
      # Venue coordinates not in GraphQL
      geocoding_strategy: :google_places,

      # Data quality
      has_coordinates: false,
      # Need enrichment
      has_ticket_urls: true,
      has_performer_info: true,
      has_images: true,
      has_descriptions: true
      # Via editorial picks
    }
  end

  def sync_job_args(options \\ %{}) do
    %{
      "source" => key(),
      "city_id" => options[:city_id],
      # Required: city database ID
      "area_id" => options[:area_id],
      # Required: RA integer area ID
      "start_date" => options[:start_date] || default_start_date(),
      "end_date" => options[:end_date] || default_end_date(),
      "page_size" => options[:page_size] || 20
    }
  end

  def detail_job_args(event_id, metadata \\ %{}) do
    %{
      "source" => key(),
      "event_id" => event_id,
      "event_metadata" => metadata
    }
  end

  def validate_config do
    with :ok <- validate_graphql_accessibility(),
         :ok <- validate_job_modules() do
      {:ok, "Resident Advisor source configuration valid"}
    end
  end

  # Private functions

  defp default_start_date do
    Date.utc_today()
    |> Date.to_iso8601()
  end

  defp default_end_date do
    Date.utc_today()
    |> Date.add(30)
    |> Date.to_iso8601()
  end

  defp validate_graphql_accessibility do
    # Simple connectivity test with minimal GraphQL query
    test_query = """
    query { __schema { queryType { name } } }
    """

    body = Jason.encode!(%{query: test_query})

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case HTTPoison.post(Config.graphql_endpoint(), body, headers, timeout: 10_000) do
      {:ok, %{status_code: 200}} ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "RA GraphQL endpoint returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach RA GraphQL endpoint: #{inspect(reason)}"}
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
