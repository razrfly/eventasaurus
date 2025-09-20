defmodule Mix.Tasks.Karnet.TestDetail do
  @moduledoc """
  Test task for Karnet scraper Phase 2 - Detail Extraction

  Usage:
    mix karnet.test_detail                    # Test with default event
    mix karnet.test_detail --url <event-url>  # Test specific event
    mix karnet.test_detail --festival         # Test festival event
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Sources.Karnet.{Client, DetailExtractor, DateParser}

  @shortdoc "Test Karnet detail extraction functionality"

  @default_event_url "https://karnet.krakowculture.pl/60682-krakow-powiazania-batruch-i-uczniowie"
  @festival_url "https://karnet.krakowculture.pl/60776-krakow-zaucha-fest-2025"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} = OptionParser.parse(args,
      switches: [url: :string, festival: :boolean],
      aliases: [u: :url, f: :festival]
    )

    url = cond do
      opts[:festival] -> @festival_url
      opts[:url] -> opts[:url]
      true -> @default_event_url
    end

    Logger.info("""
    🧪 Testing Karnet Scraper - Phase 2 (Detail Extraction)
    ========================================================
    Event URL: #{url}
    """)

    # Test 1: Fetch event page
    test_fetch_page(url)

    # Test 2: Extract event details
    test_extract_details(url)

    # Test 3: Parse dates
    test_date_parsing()

    Logger.info("\n✅ All Phase 2 tests completed!")
  end

  defp test_fetch_page(url) do
    Logger.info("\n📋 Test 1: Fetch Event Page")

    case Client.fetch_page(url) do
      {:ok, html} ->
        Logger.info("✓ Successfully fetched page")
        Logger.info("HTML size: #{byte_size(html)} bytes")
        Logger.info("Contains event content: #{String.contains?(html, "event") || String.contains?(html, "wydarzenie")}")

      {:error, reason} ->
        Logger.error("✗ Failed to fetch page: #{inspect(reason)}")
    end
  end

  defp test_extract_details(url) do
    Logger.info("\n📋 Test 2: Extract Event Details")

    case Client.fetch_page(url) do
      {:ok, html} ->
        case DetailExtractor.extract_event_details(html, url) do
          {:ok, event_data} ->
            Logger.info("✓ Successfully extracted event details")

            Logger.info("""

            Extracted Data:
            ===============
            Title: #{event_data.title}
            URL: #{event_data.url}
            Category: #{event_data.category || "N/A"}
            Date Text: #{event_data.date_text || "N/A"}
            Is Free: #{event_data.is_free}
            Is Festival: #{event_data.is_festival}
            """)

            if event_data.venue_data do
              Logger.info("""
              Venue:
              - Name: #{event_data.venue_data.name || "N/A"}
              - Address: #{event_data.venue_data.address || "N/A"}
              - City: #{event_data.venue_data.city}
              """)
            else
              Logger.info("Venue: Not found")
            end

            if event_data.description_translations do
              desc_text = case event_data.description_translations do
                %{"pl" => text} -> text
                %{"en" => text} -> text
                _ -> "No valid description"
              end
              Logger.info("Description: #{String.slice(desc_text, 0, 200)}...")
            else
              Logger.info("Description: Not found")
            end

            if event_data.ticket_url do
              Logger.info("Ticket URL: #{event_data.ticket_url}")
            else
              Logger.info("Ticket URL: Not found")
            end

            if event_data.image_url do
              Logger.info("Image URL: #{event_data.image_url}")
            else
              Logger.info("Image URL: Not found")
            end

            if event_data.performers && length(event_data.performers) > 0 do
              Logger.info("Performers: #{inspect(event_data.performers)}")
            else
              Logger.info("Performers: None found")
            end

          {:error, reason} ->
            Logger.error("✗ Failed to extract details: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.error("✗ Failed to fetch page: #{inspect(reason)}")
    end
  end

  defp test_date_parsing do
    Logger.info("\n📋 Test 3: Date Parsing")

    test_dates = [
      {"04.09.2025", "Standard date"},
      {"04.09.2025, 18:00", "Date with time"},
      {"04.09.2025 - 09.10.2025", "Date range"},
      {"04.09.2025, 18:00 - 25.09.2025", "Date range with time"},
      {"czwartek, 4 września 2025", "Polish format"},
      {"czwartek, 4 września 2025, 18:00", "Polish format with time"},
      {"4 września 2025", "Polish format without day name"},
      {"2025-09-04", "ISO format"},
      {"03.09.2025, 10:00 - 30.09.2025", "Complex range"}
    ]

    Enum.each(test_dates, fn {date_str, description} ->
      Logger.info("\nTesting: #{description}")
      Logger.info("Input: \"#{date_str}\"")

      case DateParser.parse_date_string(date_str) do
        {:ok, {start_dt, end_dt}} ->
          Logger.info("✓ Parsed successfully")
          Logger.info("  Start: #{start_dt}")
          if start_dt != end_dt do
            Logger.info("  End: #{end_dt}")
          end

        {:error, reason} ->
          Logger.warning("✗ Failed to parse: #{reason}")
      end
    end)
  end
end