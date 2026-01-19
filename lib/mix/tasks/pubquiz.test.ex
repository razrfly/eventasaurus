defmodule Mix.Tasks.Pubquiz.Test do
  @moduledoc """
  Test task for PubQuiz scraper - Venue-centric trivia events for Poland

  Usage:
    mix pubquiz.test                  # Test fetching cities and venues
    mix pubquiz.test --city warszawa  # Test specific city
    mix pubquiz.test --limit 2        # Test with limited number of cities
    mix pubquiz.test --full           # Test full extraction including venue details
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Sources.Pubquiz.{
    Client,
    Config,
    CityExtractor,
    VenueExtractor,
    DetailExtractor,
    Transformer
  }

  @shortdoc "Test PubQuiz scraper functionality (Poland trivia events)"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [city: :string, limit: :integer, full: :boolean],
        aliases: [c: :city, l: :limit, f: :full]
      )

    city = opts[:city]
    limit = opts[:limit]
    full_test = opts[:full] || false

    Logger.info("""
    🧪 Testing PubQuiz Scraper (Poland)
    ====================================
    City filter: #{city || "all"}
    City limit: #{limit || "none"}
    Full extraction: #{full_test}
    """)

    # Test 1: Configuration
    test_configuration()

    # Test 2: City extraction
    cities = test_city_extraction(city, limit)

    # Test 3: Venue extraction (first city)
    if length(cities) > 0 do
      first_city_url = List.first(cities)
      venues = test_venue_extraction(first_city_url)

      # Test 4: Detail extraction (first venue) if full test
      if full_test && length(venues) > 0 do
        first_venue = List.first(venues)
        test_venue_details(first_venue)
      end
    end

    Logger.info("\n✅ All tests completed!")
  end

  defp test_configuration do
    Logger.info("\n📋 Test 1: Configuration")
    Logger.info("Base URL: #{Config.base_url()}")
    Logger.info("Rate limit: #{Config.rate_limit()} seconds")
    Logger.info("Timeout: #{Config.timeout()} ms")
    Logger.info("Max retries: #{Config.max_retries()}")
    Logger.info("✓ Configuration test passed")
  end

  defp test_city_extraction(city_filter, limit) do
    Logger.info("\n📋 Test 2: City Extraction")

    case Client.fetch_index() do
      {:ok, html} ->
        Logger.info("✓ Successfully fetched index page")
        Logger.info("HTML size: #{byte_size(html)} bytes")

        cities = CityExtractor.extract_cities(html)
        Logger.info("✓ Extracted #{length(cities)} cities from index")

        # Filter by city if specified
        cities =
          if city_filter do
            cities
            |> Enum.filter(&String.contains?(&1, city_filter))
            |> tap(fn filtered ->
              Logger.info("  Filtered to #{length(filtered)} cities matching '#{city_filter}'")
            end)
          else
            cities
          end

        # Limit if specified
        cities =
          if limit do
            cities
            |> Enum.take(limit)
            |> tap(fn limited ->
              Logger.info("  Limited to #{length(limited)} cities")
            end)
          else
            cities
          end

        # Show all cities
        Logger.info("\nCities found:")

        cities
        |> Enum.with_index(1)
        |> Enum.each(fn {city_url, idx} ->
          # Extract city name from URL path
          city_name =
            city_url
            |> URI.parse()
            |> Map.get(:path, "")
            |> String.split("/")
            |> List.last()
            |> to_string()

          Logger.info("  #{idx}. #{city_name}")
          Logger.info("     URL: #{city_url}")
        end)

        cities

      {:error, reason} ->
        Logger.error("✗ Failed to fetch index: #{inspect(reason)}")
        []
    end
  end

  defp test_venue_extraction(city_url) do
    # Extract city name from URL path
    city_name =
      city_url
      |> URI.parse()
      |> Map.get(:path, "")
      |> String.split("/")
      |> List.last()
      |> to_string()

    Logger.info("\n📋 Test 3: Venue Extraction (#{city_name})")
    Logger.info("Fetching city page: #{city_url}")

    case Client.fetch_city_page(city_url) do
      {:ok, html} ->
        Logger.info("✓ Successfully fetched city page")
        Logger.info("HTML size: #{byte_size(html)} bytes")

        venues = VenueExtractor.extract_venues(html)
        Logger.info("✓ Extracted #{length(venues)} venues")

        if length(venues) > 0 do
          Logger.info("\nFirst 5 venues:")

          venues
          |> Enum.take(5)
          |> Enum.with_index(1)
          |> Enum.each(fn {venue, idx} ->
            Logger.info("""

            Venue #{idx}:
            - Name: #{venue.name}
            - URL: #{venue.url}
            - Image: #{venue.image_url || "N/A"}
            """)
          end)

          # Statistics
          with_images = Enum.count(venues, & &1.image_url)
          total = length(venues)
          image_percentage = if total > 0, do: round(with_images / total * 100), else: 0

          Logger.info("""

          Statistics:
          - Total venues: #{total}
          - Venues with images: #{with_images} (#{image_percentage}%)
          """)
        else
          Logger.warning("⚠️ No venues extracted - selector might need adjustment")
        end

        venues

      {:error, reason} ->
        Logger.error("✗ Failed to fetch city page: #{inspect(reason)}")
        []
    end
  end

  defp test_venue_details(venue) do
    Logger.info("\n📋 Test 4: Venue Detail Extraction")
    Logger.info("Fetching venue: #{venue.name}")
    Logger.info("URL: #{venue.url}")

    case Client.fetch_venue_page(venue.url) do
      {:ok, html} ->
        Logger.info("✓ Successfully fetched venue page")
        Logger.info("HTML size: #{byte_size(html)} bytes")

        details = DetailExtractor.extract_venue_details(html)
        Logger.info("✓ Successfully extracted venue details")

        Logger.info("""

        Venue Details:
        - Address: #{details[:address] || "N/A"}
        - Phone: #{details[:phone] || "N/A"}
        - Host: #{details[:host] || "N/A"}
        - Schedule: #{details[:schedule] || "N/A"}
        - Description: #{(details[:description] && String.slice(details[:description], 0..100)) || "N/A"}
        """)

        # Test recurrence rule parsing if schedule exists
        if details[:schedule] do
          test_recurrence_parsing(details[:schedule])
        end

      {:error, reason} ->
        Logger.error("✗ Failed to fetch venue page: #{inspect(reason)}")
    end
  end

  defp test_recurrence_parsing(schedule_text) do
    Logger.info("\n📋 Test 5: Recurrence Rule Parsing")
    Logger.info("Schedule text: #{schedule_text}")

    case Transformer.parse_schedule_to_recurrence(schedule_text) do
      {:ok, recurrence_rule} ->
        Logger.info("✓ Successfully parsed recurrence rule")

        Logger.info("""

        Recurrence Rule:
        - Frequency: #{recurrence_rule["frequency"]}
        - Days: #{Enum.join(recurrence_rule["days_of_week"], ", ")}
        - Time: #{recurrence_rule["time"]}
        - Timezone: #{recurrence_rule["timezone"]}
        """)

        # Test next occurrence calculation
        case Transformer.calculate_next_occurrence(recurrence_rule) do
          {:ok, next_dt} ->
            Logger.info(
              "✓ Next occurrence: #{Calendar.strftime(next_dt, "%A, %B %d, %Y at %H:%M")}"
            )

          {:error, reason} ->
            Logger.warning("⚠️ Could not calculate next occurrence: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("⚠️ Could not parse schedule: #{inspect(reason)}")
    end
  end
end
