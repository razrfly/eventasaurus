defmodule Mix.Tasks.Scraper.Debug do
  @moduledoc """
  Debug scraper HTML fetching and parsing.

  ## Usage

      # Debug HTML fetching
      mix scraper.debug bandsintown --city=krakow --save

      # Debug with verbose output
      mix scraper.debug bandsintown --city=krakow --verbose

  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.{Client, Extractor}

  @shortdoc "Debug scraper HTML fetching"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, remaining_args, _} = OptionParser.parse(args,
      strict: [
        city: :string,
        save: :boolean,
        verbose: :boolean,
        playwright: :boolean
      ],
      aliases: [
        c: :city,
        s: :save,
        v: :verbose,
        p: :playwright
      ]
    )

    scraper = List.first(remaining_args) || "bandsintown"

    case scraper do
      "bandsintown" ->
        debug_bandsintown(opts)

      other ->
        Logger.error("Unknown scraper: #{other}")
    end
  end

  defp debug_bandsintown(opts) do
    city = Keyword.get(opts, :city, "krakow-poland")
    save = Keyword.get(opts, :save, false)
    verbose = Keyword.get(opts, :verbose, false)
    use_playwright = Keyword.get(opts, :playwright, false)

    Logger.info("""

    =====================================
    🔍 DEBUGGING BANDSINTOWN HTML FETCH
    =====================================
    City: #{city}
    Save HTML: #{save}
    Verbose: #{verbose}
    Playwright: #{use_playwright}
    =====================================
    """)

    # Fetch the HTML
    case Client.fetch_city_page(city, use_playwright: use_playwright) do
      {:ok, html} ->
        html_size = byte_size(html)
        Logger.info("✅ Fetched HTML: #{html_size} bytes")

        # Check for JavaScript indicators
        cond do
          String.contains?(html, "View all") ->
            Logger.warning("⚠️  Found 'View all' button - JavaScript required")
          String.contains?(html, "__NEXT_DATA__") ->
            Logger.warning("⚠️  Found Next.js app - JavaScript required")
          String.contains?(html, "React") ->
            Logger.warning("⚠️  Found React - JavaScript required")
          true ->
            Logger.info("✅ Page appears to be server-rendered")
        end

        # Try to extract events
        case Extractor.extract_events_from_city_page(html) do
          {:ok, events} ->
            Logger.info("📋 Extracted #{length(events)} events")

            if verbose && length(events) > 0 do
              Logger.info("Sample events:")
              Enum.take(events, 3) |> Enum.each(fn event ->
                Logger.info("  - #{inspect(event, pretty: true)}")
              end)
            end

          {:error, reason} ->
            Logger.error("❌ Failed to extract events: #{inspect(reason)}")
        end

        # Look for event indicators in HTML
        event_indicators = [
          {"[data-testid='event-card']", length(Regex.scan(~r/data-testid=["']event-card["']/, html))},
          {".event-card", length(Regex.scan(~r/class=["'][^"']*event-card[^"']*["']/, html))},
          {"EventCard", length(Regex.scan(~r/EventCard/, html))},
          {"href='/e/'", length(Regex.scan(~r/href=["']\/e\//, html))},
          {"data-event-id", length(Regex.scan(~r/data-event-id/, html))}
        ]

        Logger.info("\n📊 Event Indicators Found:")
        Enum.each(event_indicators, fn {selector, count} ->
          if count > 0 do
            Logger.info("  ✅ #{selector}: #{count} occurrences")
          else
            Logger.info("  ❌ #{selector}: not found")
          end
        end)

        # Save HTML if requested
        if save do
          filename = "debug_#{city}_#{System.system_time(:second)}.html"
          path = Path.join(["tmp", filename])
          File.mkdir_p!("tmp")
          File.write!(path, html)
          Logger.info("\n💾 HTML saved to: #{path}")
        end

        # Show a snippet of the HTML
        if verbose do
          Logger.info("\n📄 HTML Snippet (first 1000 chars):")
          Logger.info(String.slice(html, 0, 1000))
        end

      {:error, :playwright_not_configured} ->
        Logger.error("""

        ❌ PLAYWRIGHT NOT CONFIGURED
        =====================================
        The scraper needs Playwright for JavaScript rendering.
        This page requires clicking "View all" and scrolling.
        =====================================
        """)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch HTML: #{inspect(reason)}")
    end
  end
end