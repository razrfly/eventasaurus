defmodule Mix.Tasks.Scraper.Run do
  @moduledoc """
  Run scrapers through Oban for production use.

  ## Usage

      # Run scraper for Krakow
      mix scraper.run bandsintown --city=krakow

      # Run scraper with delay
      mix scraper.run bandsintown --city=krakow --delay=60

      # Run multiple cities
      mix scraper.run bandsintown --cities=krakow-poland,warsaw-poland,berlin-germany

  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.CityIndexJob

  @shortdoc "Run scrapers through Oban"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, remaining_args, _} = OptionParser.parse(args,
      strict: [
        city: :string,
        cities: :string,
        delay: :integer,
        playwright: :boolean
      ],
      aliases: [
        c: :city,
        d: :delay,
        p: :playwright
      ]
    )

    # Get the scraper name
    scraper = List.first(remaining_args) || "bandsintown"

    case scraper do
      "bandsintown" ->
        run_bandsintown(opts)

      other ->
        Logger.error("Unknown scraper: #{other}")
        Logger.info("Available scrapers: bandsintown")
    end
  end

  defp run_bandsintown(opts) do
    use_playwright = Keyword.get(opts, :playwright, false)
    delay = Keyword.get(opts, :delay, 0)

    # Get cities to process
    cities = case {Keyword.get(opts, :cities), Keyword.get(opts, :city)} do
      {nil, nil} -> ["krakow-poland"]
      {nil, city} -> [city]
      {cities_str, _} -> String.split(cities_str, ",")
    end

    Logger.info("""

    =====================================
    🚀 SCHEDULING BANDSINTOWN SCRAPER JOBS
    =====================================
    Cities: #{Enum.join(cities, ", ")}
    Delay between jobs: #{delay}s
    Playwright: #{use_playwright}
    =====================================
    """)

    # Schedule jobs
    jobs = Enum.with_index(cities, fn city, index ->
      scheduled_at = DateTime.add(DateTime.utc_now(), index * delay, :second)

      job_args = %{
        "city_slug" => String.trim(city),
        "use_playwright" => use_playwright
      }

      job = %{
        queue: :scraper,
        worker: "EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.CityIndexJob",
        args: job_args,
        scheduled_at: scheduled_at
      }

      case Oban.insert(CityIndexJob.new(job_args, scheduled_at: scheduled_at)) do
        {:ok, job} ->
          Logger.info("✅ Scheduled job for #{city} at #{scheduled_at}")
          {:ok, job}

        {:error, changeset} ->
          Logger.error("❌ Failed to schedule job for #{city}: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    end)

    success_count = Enum.count(jobs, fn {status, _} -> status == :ok end)

    Logger.info("""

    =====================================
    SCHEDULING COMPLETE
    =====================================
    Successfully scheduled: #{success_count}/#{length(cities)} jobs
    Check Oban dashboard or logs for progress
    =====================================
    """)
  end
end