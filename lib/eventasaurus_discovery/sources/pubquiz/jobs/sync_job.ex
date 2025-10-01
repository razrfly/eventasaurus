defmodule EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob do
  @moduledoc """
  Main orchestrator for PubQuiz.pl scraping.

  Country-level sync that:
  1. Fetches list of all Polish cities from pubquiz.pl
  2. Schedules CityJob for each city to fetch venues
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.Pubquiz.{Client, CityExtractor, Jobs.CityJob}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🎯 Starting PubQuiz Poland sync...")

    source = get_or_create_pubquiz_source()
    limit = args["limit"]

    with {:ok, html} <- Client.fetch_index(),
         city_urls <- CityExtractor.extract_cities(html),
         city_urls <- maybe_limit_cities(city_urls, limit),
         scheduled_count <- schedule_city_jobs(city_urls, source.id) do
      Logger.info("""
      ✅ PubQuiz sync completed
      Cities found: #{length(city_urls)}
      City jobs scheduled: #{scheduled_count}
      """)

      {:ok,
       %{
         cities_found: length(city_urls),
         jobs_scheduled: scheduled_count,
         source: "pubquiz-pl"
       }}
    else
      {:error, reason} = error ->
        Logger.error("❌ PubQuiz sync failed: #{inspect(reason)}")
        error
    end
  end

  defp maybe_limit_cities(city_urls, nil), do: city_urls

  defp maybe_limit_cities(city_urls, limit) when is_integer(limit) do
    Logger.info("🧪 Testing mode: limiting to #{limit} cities")
    Enum.take(city_urls, limit)
  end

  defp schedule_city_jobs(city_urls, source_id) do
    city_urls
    |> Enum.with_index()
    |> Enum.map(fn {city_url, index} ->
      # Stagger jobs slightly to avoid thundering herd
      delay_seconds = index * 5
      scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

      job_args = %{
        "city_url" => city_url,
        "source_id" => source_id
      }

      CityJob.new(job_args, scheduled_at: scheduled_at)
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

    case Repo.get_by(Source, slug: PubquizSource.key()) do
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
        |> Repo.insert!()

      source ->
        source
    end
  end
end
