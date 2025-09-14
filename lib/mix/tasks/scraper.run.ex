defmodule Mix.Tasks.Scraper.Run do
  @moduledoc """
  Run scrapers through Oban for production use.

  ## Usage

      # Run scraper for specific city with event limit
      mix scraper.run bandsintown --city="Kraków" --max-events=20

      # Run scraper for Warsaw
      mix scraper.run bandsintown --city="Warsaw" --max-events=15

      # Run scraper for Katowice
      mix scraper.run bandsintown --city="Katowice" --max-events=10

  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.CityIndexJob
  import Ecto.Query

  @shortdoc "Run scrapers through Oban"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, remaining_args, _} = OptionParser.parse(args,
      strict: [
        city: :string,
        max_events: :integer
      ]
    )

    # Get the scraper name
    scraper = List.first(remaining_args) || "bandsintown"

    case scraper do
      "bandsintown" ->
        run_bandsintown(opts)

      other ->
        IO.puts("❌ Unknown scraper: #{other}")
        IO.puts("Available scrapers: bandsintown")
        System.halt(1)
    end
  end

  defp run_bandsintown(opts) do
    city_name = Keyword.get(opts, :city)
    max_events = Keyword.get(opts, :max_events, 10)

    # Validate required parameters
    if is_nil(city_name) do
      IO.puts("❌ Error: --city parameter is required")
      IO.puts("Usage: mix scraper.run bandsintown --city=\"Kraków\" --max-events=20")
      System.halt(1)
    end

    # Find city in database
    city = from(c in City,
      where: ilike(c.name, ^city_name),
      preload: :country
    ) |> Repo.one()

    if is_nil(city) do
      IO.puts("❌ Error: City '#{city_name}' not found in database")
      IO.puts("Available cities:")

      available_cities = from(c in City, select: c.name, order_by: c.name) |> Repo.all()
      for city_name <- Enum.take(available_cities, 10) do
        IO.puts("  - #{city_name}")
      end

      System.halt(1)
    end

    IO.puts("🌍 Found city: #{city.name} (#{city.latitude}, #{city.longitude})")

    # Calculate max_pages from max_events (roughly 36 events per page)
    max_pages = max(1, ceil(max_events / 36))

    # Schedule CityIndexJob
    job_args = %{
      "city_id" => city.id,
      "city_name" => city.name,
      "latitude" => city.latitude,
      "longitude" => city.longitude,
      "max_pages" => max_pages
    }

    case CityIndexJob.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        IO.puts("🚀 Scheduled scraping job for #{city.name} (max #{max_events} events)")
        IO.puts("📋 Job ID: #{job.id} - Status: queued")
        IO.puts("✅ Events will be scraped automatically. Check logs for progress.")

      {:error, changeset} ->
        IO.puts("❌ Failed to schedule job: #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end
end