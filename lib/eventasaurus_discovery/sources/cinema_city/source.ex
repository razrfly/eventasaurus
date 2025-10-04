defmodule EventasaurusDiscovery.Sources.CinemaCity.Source do
  @moduledoc """
  Cinema City source configuration for the unified discovery system.

  This source uses Cinema City's public JSON API to fetch movie showtimes
  from Cinema City cinemas across Poland. It serves as a primary source
  for Cinema City screenings, taking precedence over Cinema City listings
  found via the Kino Kraków aggregator.

  ## Features
  - JSON API (no HTML scraping required)
  - Direct source from cinema chain (authoritative data)
  - TMDB matching for rich movie metadata
  - Multi-cinema support (32+ locations across Poland)
  - Initial focus: Kraków (3 cinemas)

  ## Priority
  Cinema City API is a primary source (priority: 15) that takes precedence
  over secondary aggregators when the same screening is found in both.
  """

  alias EventasaurusDiscovery.Sources.CinemaCity.{
    Config,
    Jobs.SyncJob
  }

  def name, do: "Cinema City"

  def key, do: "cinema-city"

  def enabled?, do: Application.get_env(:eventasaurus_discovery, :cinema_city_enabled, true)

  # Movies should have high priority as they're time-sensitive
  # Same priority as Kino Krakow (15)
  def priority, do: 15

  def config do
    %{
      # Source identification (required by SourceStore)
      slug: key(),
      name: name(),
      priority: priority(),
      website_url: Config.base_url(),
      base_url: Config.api_base_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      rate_limit: Config.rate_limit(),
      timeout: Config.timeout(),
      retry_attempts: Config.max_retries(),
      retry_delay_ms: 5_000,
      max_retries: Config.max_retries(),

      # Localized settings
      city: "Kraków",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL",

      # Job configuration
      sync_job: SyncJob,

      # Queue settings
      sync_queue: :discovery,

      # Features
      supports_api: true,
      supports_pagination: false,
      supports_date_filtering: true,
      supports_venue_details: true,
      supports_movie_metadata: true,
      supports_tmdb_matching: true,
      supports_ticket_info: true,

      # Cinema City specific
      site_id: Config.site_id(),
      days_ahead: Config.days_ahead(),
      target_cities: Config.target_cities()
    }
  end

  def sync_job_args(options \\ %{}) do
    %{
      "source" => key(),
      "city" => options[:city] || "Kraków",
      "date" => options[:date] || Date.utc_today() |> Date.to_iso8601(),
      "days_ahead" => options[:days_ahead] || Config.days_ahead()
    }
  end

  def validate_config do
    with :ok <- validate_api_accessibility(),
         :ok <- validate_job_modules() do
      {:ok, "Cinema City source configuration valid"}
    end
  end

  defp validate_api_accessibility do
    # Test the cinema list endpoint
    until_date = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()
    test_url = Config.cinema_list_url(until_date)

    case HTTPoison.get(test_url, Config.headers(), timeout: Config.timeout()) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "Cinema City API returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Cinema City API: #{inspect(reason)}"}
    end
  end

  defp validate_job_modules do
    if Code.ensure_loaded?(SyncJob) do
      :ok
    else
      {:error, "SyncJob module not found"}
    end
  end
end
