defmodule Mix.Tasks.Karnet.Test do
  @moduledoc """
  Test task for Karnet scraper Phase 1 - Index Scraping

  Usage:
    mix karnet.test              # Test fetching first page
    mix karnet.test --pages 2    # Test fetching multiple pages
    mix karnet.test --extract    # Test extraction from fetched pages
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Sources.Karnet.{Client, Config, IndexExtractor}

  @shortdoc "Test Karnet index scraping functionality"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} = OptionParser.parse(args,
      switches: [pages: :integer, extract: :boolean],
      aliases: [p: :pages, e: :extract]
    )

    pages_to_fetch = opts[:pages] || 1
    should_extract = opts[:extract] || false

    Logger.info("""
    🧪 Testing Karnet Scraper - Phase 1
    ====================================
    Pages to fetch: #{pages_to_fetch}
    Extract events: #{should_extract}
    """)

    # Test 1: Configuration
    test_configuration()

    # Test 2: Fetch single page
    test_fetch_single_page()

    # Test 3: Fetch multiple pages if requested
    if pages_to_fetch > 1 do
      test_fetch_multiple_pages(pages_to_fetch)
    end

    # Test 4: Extract events if requested
    if should_extract do
      test_event_extraction(pages_to_fetch)
    end

    Logger.info("\n✅ All tests completed!")
  end

  defp test_configuration do
    Logger.info("\n📋 Test 1: Configuration")
    Logger.info("Base URL: #{Config.base_url()}")
    Logger.info("Rate limit: #{Config.rate_limit()} seconds")
    Logger.info("Timeout: #{Config.timeout()} ms")
    Logger.info("Events URL (page 1): #{Config.build_events_url(1)}")
    Logger.info("Events URL (page 2): #{Config.build_events_url(2)}")
    Logger.info("✓ Configuration test passed")
  end

  defp test_fetch_single_page do
    Logger.info("\n📋 Test 2: Fetch Single Page")
    url = Config.build_events_url(1)
    Logger.info("Fetching: #{url}")

    case Client.fetch_page(url) do
      {:ok, html} ->
        Logger.info("✓ Successfully fetched page")
        Logger.info("HTML size: #{byte_size(html)} bytes")
        Logger.info("Contains 'wydarzenia': #{String.contains?(html, "wydarzenia")}")
        Logger.info("Contains 'Kraków': #{String.contains?(html, "Kraków") || String.contains?(html, "Krakow")}")

        # Check for event-like content
        has_links = String.contains?(html, "href")
        has_dates = Regex.match?(~r/\d{1,2}\.\d{1,2}\.\d{4}/, html) ||
                   Regex.match?(~r/\d{4}-\d{2}-\d{2}/, html)

        Logger.info("Has links: #{has_links}")
        Logger.info("Has date patterns: #{has_dates}")

        if has_links && has_dates do
          Logger.info("✓ Page appears to contain event data")
        else
          Logger.warning("⚠️ Page might not contain expected event data")
        end

      {:error, reason} ->
        Logger.error("✗ Failed to fetch page: #{inspect(reason)}")
    end
  end

  defp test_fetch_multiple_pages(max_pages) do
    Logger.info("\n📋 Test 3: Fetch Multiple Pages (#{max_pages})")

    case Client.fetch_all_index_pages(max_pages) do
      {:ok, pages} ->
        Logger.info("✓ Successfully fetched #{length(pages)} pages")

        Enum.each(pages, fn {page_num, html} ->
          Logger.info("  Page #{page_num}: #{byte_size(html)} bytes")
        end)

      {:error, reason} ->
        Logger.error("✗ Failed to fetch pages: #{inspect(reason)}")
    end
  end

  defp test_event_extraction(max_pages) do
    Logger.info("\n📋 Test 4: Event Extraction")

    case Client.fetch_all_index_pages(max_pages) do
      {:ok, pages} ->
        Logger.info("Fetched #{length(pages)} pages, extracting events...")

        events = IndexExtractor.extract_events_from_pages(pages)
        Logger.info("✓ Extracted #{length(events)} total events")

        if length(events) > 0 do
          # Show first few events as examples
          Logger.info("\nFirst 3 events:")
          events
          |> Enum.take(3)
          |> Enum.with_index(1)
          |> Enum.each(fn {event, idx} ->
            Logger.info("""

            Event #{idx}:
            - Title: #{event.title || "N/A"}
            - URL: #{event.url || "N/A"}
            - Date: #{event.date_text || "N/A"}
            - Venue: #{event.venue_name || "N/A"}
            - Category: #{event.category || "N/A"}
            """)
          end)

          # Statistics
          with_dates = Enum.count(events, & &1.date_text)
          with_venues = Enum.count(events, & &1.venue_name)
          with_categories = Enum.count(events, & &1.category)

          total_events = length(events)
          date_percentage = if total_events > 0, do: round(with_dates / total_events * 100), else: 0
          venue_percentage = if total_events > 0, do: round(with_venues / total_events * 100), else: 0
          category_percentage = if total_events > 0, do: round(with_categories / total_events * 100), else: 0

          Logger.info("""

          Statistics:
          - Events with dates: #{with_dates}/#{total_events} (#{date_percentage}%)
          - Events with venues: #{with_venues}/#{total_events} (#{venue_percentage}%)
          - Events with categories: #{with_categories}/#{total_events} (#{category_percentage}%)
          """)

          # Check for unique URLs
          unique_urls = events |> Enum.map(& &1.url) |> Enum.uniq() |> length()
          if unique_urls < length(events) do
            Logger.warning("⚠️ Found duplicate URLs: #{length(events) - unique_urls} duplicates")
          else
            Logger.info("✓ All event URLs are unique")
          end
        else
          Logger.warning("⚠️ No events extracted - selector might need adjustment")
        end

      {:error, reason} ->
        Logger.error("✗ Failed to fetch pages for extraction: #{inspect(reason)}")
    end
  end
end