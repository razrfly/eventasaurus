defmodule Mix.Tasks.Scraper.PaginationTest do
  @moduledoc """
  Test pagination functionality for scrapers.

  ## Usage

      # Test pagination for Bandsintown
      mix scraper.pagination_test bandsintown --city=krakow-poland --max-pages=3

  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client

  @shortdoc "Test scraper pagination"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, remaining_args, _} = OptionParser.parse(args,
      strict: [
        city: :string,
        max_pages: :integer
      ],
      aliases: [
        c: :city,
        m: :max_pages
      ]
    )

    scraper = List.first(remaining_args) || "bandsintown"

    case scraper do
      "bandsintown" ->
        test_bandsintown_pagination(opts)

      other ->
        Logger.error("Unknown scraper: #{other}")
    end
  end

  defp test_bandsintown_pagination(opts) do
    city = Keyword.get(opts, :city, "krakow-poland")
    max_pages = Keyword.get(opts, :max_pages, 3)

    Logger.info("""

    =====================================
    🧪 TESTING BANDSINTOWN PAGINATION
    =====================================
    City: #{city}
    Max pages: #{max_pages}
    =====================================
    """)

    # Test fetching all events with pagination
    # For testing, use dummy coordinates (this task is for pagination testing only)
    case Client.fetch_all_city_events(50.0647, 19.945, city, max_pages: max_pages) do
      {:ok, all_events} ->
        Logger.info("""

        =====================================
        ✅ PAGINATION TEST SUCCESSFUL
        =====================================
        Total events collected: #{length(all_events)}
        =====================================
        """)

        # Show sample events
        if length(all_events) > 0 do
          Logger.info("\n📋 Sample events:")
          all_events
          |> Enum.take(5)
          |> Enum.with_index(1)
          |> Enum.each(fn {event, idx} ->
            Logger.info("""
            #{idx}. #{event[:artist_name]}
               Venue: #{event[:venue_name]}
               Date: #{event[:date]}
               URL: #{event[:url]}
            """)
          end)

          # Show events from different pages
          if length(all_events) > 36 do
            Logger.info("\n📄 Events from page 2 (sample):")
            all_events
            |> Enum.slice(36, 5)
            |> Enum.with_index(37)
            |> Enum.each(fn {event, idx} ->
              Logger.info("""
              #{idx}. #{event[:artist_name]}
                 Venue: #{event[:venue_name]}
              """)
            end)
          end
        end

    end
  end
end