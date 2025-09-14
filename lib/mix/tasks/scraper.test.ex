defmodule Mix.Tasks.Scraper.Test do
  @moduledoc """
  Test scraper functionality for debugging and development.

  ## Usage

      # Test scraper for a city by ID
      mix scraper.test bandsintown --city-id=1 --limit=5

      # Test scraper for a city by name (will look up in database)
      mix scraper.test bandsintown --city-name=krakow --limit=5

      # Test without limit
      mix scraper.test bandsintown --city-id=1

      # Test with different cities (using database IDs)
      mix scraper.test bandsintown --city-id=2  # Warsaw
      mix scraper.test bandsintown --city-id=3  # Katowice

      # Legacy: Test with city slug (for backwards compatibility)
      mix scraper.test bandsintown --city=krakow-poland

      # Test with Playwright (when configured)
      mix scraper.test bandsintown --city-id=1 --playwright

  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.CityIndexJob

  @shortdoc "Test scraper functionality"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, remaining_args, _} = OptionParser.parse(args,
      strict: [
        city: :string,          # Legacy: city slug
        city_id: :integer,      # New: city database ID
        city_name: :string,     # New: city name to look up
        limit: :integer,
        playwright: :boolean,
        verbose: :boolean,
        max_pages: :integer
      ],
      aliases: [
        c: :city,
        l: :limit,
        p: :playwright,
        v: :verbose
      ]
    )

    # Get the scraper name (first argument)
    scraper = List.first(remaining_args) || "bandsintown"

    # Execute based on scraper
    case scraper do
      "bandsintown" ->
        test_bandsintown(opts)

      other ->
        Logger.error("Unknown scraper: #{other}")
        Logger.info("Available scrapers: bandsintown")
    end
  end

  defp test_bandsintown(opts) do
    # Determine which city to use
    {job_args, city_display} = cond do
      # Option 1: City ID provided
      city_id = Keyword.get(opts, :city_id) ->
        city = Repo.get!(City, city_id) |> Repo.preload(:country)
        {%{"city_id" => city_id}, "#{city.name}, #{city.country.name} (ID: #{city_id})"}

      # Option 2: City name provided
      city_name = Keyword.get(opts, :city_name) ->
        case Repo.get_by(City, slug: String.downcase(city_name)) do
          nil ->
            Logger.error("City not found: #{city_name}")
            Logger.info("Available cities in database:")
            Repo.all(City)
            |> Repo.preload(:country)
            |> Enum.each(fn c ->
              Logger.info("  - #{c.name} (#{c.country.name}) - ID: #{c.id}, slug: #{c.slug}")
            end)
            System.halt(1)
          city ->
            city = Repo.preload(city, :country)
            {%{"city_id" => city.id}, "#{city.name}, #{city.country.name} (ID: #{city.id})"}
        end

      # Option 3: Legacy city slug
      city_slug = Keyword.get(opts, :city) ->
        Logger.warning("Using legacy city slug. Consider using --city-id or --city-name instead.")
        {%{"city_slug" => city_slug}, city_slug}

      # Default: Use Kraków
      true ->
        city = Repo.get!(City, 1) |> Repo.preload(:country)
        {%{"city_id" => 1}, "#{city.name}, #{city.country.name} (ID: 1, default)"}
    end

    limit = Keyword.get(opts, :limit)
    use_playwright = Keyword.get(opts, :playwright, false)
    verbose = Keyword.get(opts, :verbose, false)
    max_pages = Keyword.get(opts, :max_pages, 5)

    Logger.info("""

    =====================================
    🧪 TESTING BANDSINTOWN SCRAPER
    =====================================
    City: #{city_display}
    Limit: #{limit || "none"}
    Max pages: #{max_pages}
    Playwright: #{use_playwright}
    Verbose: #{verbose}
    =====================================
    """)

    # Add additional options to job args
    job_args = job_args
    |> Map.put("use_playwright", use_playwright)
    |> Map.put("max_pages", max_pages)

    job_args = if limit, do: Map.put(job_args, "limit", limit), else: job_args

    # Execute the job directly (synchronously for testing)
    result = CityIndexJob.perform(%Oban.Job{
      id: System.unique_integer([:positive]),
      args: job_args
    })

    case result do
      {:ok, metadata} ->
        Logger.info("""

        ✅ SCRAPER TEST COMPLETED SUCCESSFULLY
        =====================================
        Total events found: #{metadata.total_events}
        Events processed: #{metadata.processed_count}
        Jobs enqueued: #{metadata.enqueued_count}
        Source ID: #{metadata.source_id}
        =====================================
        """)

        if verbose do
          Logger.info("""
          Full metadata:
          #{inspect(metadata, pretty: true)}
          """)
        end

      {:error, :playwright_not_configured} ->
        Logger.warning("""

        ⚠️  PLAYWRIGHT NOT CONFIGURED
        =====================================
        The page requires JavaScript rendering.
        Playwright integration is not yet configured.

        To use Playwright:
        1. Ensure playwright MCP server is running
        2. Use the --playwright flag

        Trying simple HTTP fetch instead...
        =====================================
        """)

      {:error, :javascript_required} ->
        Logger.error("""

        ❌ JAVASCRIPT REQUIRED
        =====================================
        This page requires JavaScript rendering.
        The "View all" button and scrolling need browser automation.

        Please configure Playwright to scrape this page.
        =====================================
        """)

      {:error, reason} ->
        Logger.error("""

        ❌ SCRAPER TEST FAILED
        =====================================
        Error: #{inspect(reason)}
        =====================================
        """)
    end
  end
end