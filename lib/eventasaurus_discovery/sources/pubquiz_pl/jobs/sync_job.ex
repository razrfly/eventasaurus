defmodule EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob do
  @moduledoc """
  Main orchestrator for PubQuiz.pl scraping.

  Country-level sync that:
  1. Fetches list of all Polish cities from pubquiz.pl
  2. Schedules CityJob for each city to fetch venues
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Metrics.MetricsTracker
  alias EventasaurusDiscovery.Sources.Pubquiz.{Client, CityExtractor, Jobs.CityJob}

  # BaseJob callbacks - not used for country-level orchestration
  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # PubQuiz uses country-level orchestration instead of city-based fetch
    Logger.warning("⚠️ fetch_events called on country-level source - not used")
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # PubQuiz transformation happens in detail jobs
    Logger.debug("🔄 transform_events called (not used in orchestration pattern)")
    raw_events
  end

  @doc """
  Source configuration for BaseJob.
  """
  def source_config do
    alias EventasaurusDiscovery.Sources.Pubquiz.Source, as: PubquizSource
    alias EventasaurusDiscovery.Sources.Pubquiz.Config

    %{
      name: PubquizSource.name(),
      slug: PubquizSource.key(),
      website_url: "https://pubquiz.pl",
      priority: PubquizSource.priority(),
      domains: ["trivia", "entertainment"],
      aggregate_on_index: true,
      aggregation_type: "SocialEvent",
      config: %{
        "rate_limit_seconds" => Config.rate_limit(),
        "max_requests_per_hour" => 300,
        "language" => "pl",
        "supports_recurring_events" => true,
        "discovery_method" => "country_orchestration"
      }
    }
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "pubquiz_sync_#{Date.utc_today()}"
    Logger.info("🎯 Starting PubQuiz Poland sync...")

    source = get_or_create_pubquiz_source()
    limit = args["limit"]
    force = args["force"] || false

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    with {:ok, html} <- Client.fetch_index(),
         city_urls <- CityExtractor.extract_cities(html),
         city_urls <- maybe_limit_cities(city_urls, limit),
         scheduled_count <- schedule_city_jobs(city_urls, source.id, force) do
      Logger.info("""
      ✅ PubQuiz sync completed
      Cities found: #{length(city_urls)}
      City jobs scheduled: #{scheduled_count}
      """)

      MetricsTracker.record_success(job, external_id)

      {:ok,
       %{
         cities_found: length(city_urls),
         jobs_scheduled: scheduled_count,
         source: "pubquiz-pl"
       }}
    else
      {:error, reason} = error ->
        Logger.error("❌ PubQuiz sync failed: #{inspect(reason)}")
        MetricsTracker.record_failure(job, "PubQuiz sync failed: #{inspect(reason)}", external_id)
        error
    end
  end

  defp maybe_limit_cities(city_urls, nil), do: city_urls

  defp maybe_limit_cities(city_urls, limit) when is_integer(limit) do
    Logger.info("🧪 Testing mode: limiting to #{limit} cities")
    Enum.take(city_urls, limit)
  end

  defp schedule_city_jobs(city_urls, source_id, force) do
    city_urls
    |> Enum.with_index()
    |> Enum.map(fn {city_url, index} ->
      # Stagger jobs slightly to avoid thundering herd
      delay_seconds = index * 5

      job_args = %{
        "city_url" => city_url,
        "source_id" => source_id,
        "force" => force
      }

      CityJob.new(job_args, schedule_in: delay_seconds)
      |> Oban.insert()
    end)
    |> Enum.count(fn
      {:ok, _} -> true
      _ -> false
    end)
  end

  defp get_or_create_pubquiz_source do
    alias EventasaurusDiscovery.Sources.Pubquiz.Source, as: PubquizSource
    alias EventasaurusDiscovery.Sources.Pubquiz.Config

    case JobRepo.get_by(Source, slug: PubquizSource.key()) do
      nil ->
        Logger.info("Creating PubQuiz source record...")

        %Source{}
        |> Source.changeset(%{
          name: PubquizSource.name(),
          slug: PubquizSource.key(),
          website_url: "https://pubquiz.pl",
          priority: PubquizSource.priority(),
          config: %{
            "rate_limit_seconds" => Config.rate_limit(),
            "max_requests_per_hour" => 300,
            "language" => "pl",
            "supports_recurring_events" => true
          }
        })
        |> JobRepo.insert!()

      source ->
        source
    end
  end
end
