defmodule Mix.Tasks.Scraper.TestAllCities do
  @moduledoc """
  Test scraper with all cities in the database.

  ## Usage

      # Test all cities with default settings
      mix scraper.test_all_cities

      # Test with specific limit per city
      mix scraper.test_all_cities --limit=10

      # Test with more pages
      mix scraper.test_all_cities --max-pages=10

      # Test specific cities by IDs
      mix scraper.test_all_cities --city-ids=1,2,3
  """

  use Mix.Task
  require Logger
  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.CityIndexJob

  @shortdoc "Test scraper with all cities in database"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} = OptionParser.parse(args,
      strict: [
        city_ids: :string,
        limit: :integer,
        max_pages: :integer,
        delay: :integer  # Delay between cities in seconds
      ]
    )

    # Get cities to test
    cities = if city_ids = opts[:city_ids] do
      ids = city_ids
      |> String.split(",")
      |> Enum.map(&String.to_integer/1)

      Repo.all(from c in City, where: c.id in ^ids, preload: :country)
    else
      Repo.all(City) |> Repo.preload(:country)
    end

    if Enum.empty?(cities) do
      Logger.error("No cities found in database!")
      Logger.info("Please run: mix run priv/repo/seeds.exs")
      System.halt(1)
    end

    limit = opts[:limit]
    max_pages = opts[:max_pages] || 5
    delay = opts[:delay] || 5

    Logger.info("""

    =====================================
    🌍 TESTING ALL CITIES
    =====================================
    Cities to test: #{length(cities)}
    Limit per city: #{limit || "none"}
    Max pages per city: #{max_pages}
    Delay between cities: #{delay}s
    =====================================
    """)

    # Test each city
    results = cities
    |> Enum.with_index(1)
    |> Enum.map(fn {city, index} ->
      Logger.info("""

      -------------------------------------
      Testing city #{index}/#{length(cities)}: #{city.name}, #{city.country.name}
      Coordinates: (#{city.latitude}, #{city.longitude})
      -------------------------------------
      """)

      # Create job args
      job_args = %{
        "city_id" => city.id,
        "max_pages" => max_pages
      }

      job_args = if limit, do: Map.put(job_args, "limit", limit), else: job_args

      # Execute the job
      result = CityIndexJob.perform(%Oban.Job{
        id: System.unique_integer([:positive]),
        args: job_args
      })

      # Delay between cities (except for the last one)
      if index < length(cities) do
        Logger.info("⏳ Waiting #{delay}s before next city...")
        Process.sleep(delay * 1000)
      end

      {city, result}
    end)

    # Print summary
    Logger.info("""

    =====================================
    📊 SUMMARY
    =====================================
    """)

    successful = Enum.filter(results, fn {_, result} ->
      match?({:ok, _}, result)
    end)

    failed = Enum.filter(results, fn {_, result} ->
      match?({:error, _}, result)
    end)

    Enum.each(successful, fn {city, {:ok, metadata}} ->
      Logger.info("""
      ✅ #{city.name}, #{city.country.name}:
         Events found: #{metadata.total_events}
         Events processed: #{metadata.processed_count}
      """)
    end)

    if not Enum.empty?(failed) do
      Logger.error("Failed cities:")
      Enum.each(failed, fn {city, {:error, reason}} ->
        Logger.error("  ❌ #{city.name}: #{inspect(reason)}")
      end)
    end

    Logger.info("""

    Total successful: #{length(successful)}/#{length(cities)}
    Total events found: #{successful |> Enum.map(fn {_, {:ok, m}} -> m.total_events end) |> Enum.sum()}
    =====================================
    """)
  end
end