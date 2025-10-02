defmodule EventasaurusDiscovery.Sources.KinoKrakow.Source do
  @moduledoc """
  Kino Krakow source configuration for movie showtimes in Kraków.

  This source scrapes actual theater programming and matches to TMDB for rich metadata.
  """

  alias EventasaurusDiscovery.Sources.KinoKrakow.{
    Config,
    Jobs.SyncJob
  }

  def name, do: "Kino Krakow"

  def key, do: "kino-krakow"

  def enabled?, do: Application.get_env(:eventasaurus_discovery, :kino_krakow_enabled, true)

  # Movies should have high priority as they're time-sensitive
  def priority, do: 15

  def config do
    %{
      # Source identification (required by SourceStore)
      slug: key(),
      name: name(),
      priority: priority(),
      website_url: Config.base_url(),

      base_url: Config.base_url(),
      rate_limit_ms: Config.rate_limit() * 1000,
      rate_limit: Config.rate_limit(),
      max_pages: Config.max_pages(),
      timeout: Config.timeout(),
      retry_attempts: 2,
      retry_delay_ms: 5_000,
      max_retries: 2,

      # Localized settings
      city: "Kraków",
      country: "Poland",
      timezone: "Europe/Warsaw",
      locale: "pl_PL",

      # Job configuration
      sync_job: SyncJob,

      # Queue settings
      sync_queue: :scraper_index,

      # Features
      supports_api: false,
      supports_pagination: false,
      supports_date_filtering: true,
      supports_venue_details: true,
      supports_movie_metadata: true,
      supports_tmdb_matching: true,
      supports_ticket_info: true
    }
  end

  def sync_job_args(options \\ %{}) do
    %{
      "source" => key(),
      "date" => options[:date] || Date.utc_today() |> Date.to_iso8601()
    }
  end

  def validate_config do
    with :ok <- validate_url_accessibility(),
         :ok <- validate_job_modules() do
      {:ok, "Kino Krakow source configuration valid"}
    end
  end

  defp validate_url_accessibility do
    case HTTPoison.get(Config.base_url(), [], timeout: 5_000) do
      {:ok, %{status_code: status}} when status in 200..299 ->
        :ok

      {:ok, %{status_code: status}} ->
        {:error, "Kino Krakow returned status #{status}"}

      {:error, reason} ->
        {:error, "Cannot reach Kino Krakow: #{inspect(reason)}"}
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
