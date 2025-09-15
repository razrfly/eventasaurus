defmodule Mix.Tasks.Ticketmaster.Test do
  @moduledoc """
  Test Ticketmaster Discovery API connection and retrieve sample data from Poland.

  Usage:
    mix ticketmaster.test
  """

  use Mix.Task
  require Logger

  @base_url "https://app.ticketmaster.com/discovery/v2"

  @shortdoc "Test Ticketmaster API connection with Poland data"

  def run(_args) do
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:tesla)

    api_key = System.get_env("TICKETMASTER_CONSUMER_KEY")

    if is_nil(api_key) or api_key == "" do
      Logger.error("TICKETMASTER_CONSUMER_KEY not found in environment variables")
      System.halt(1)
    end

    Logger.info("Starting Ticketmaster API tests with key: #{String.slice(api_key, 0..7)}...")

    # Test 1: Basic connection with Poland events
    test_basic_connection(api_key)

    # Test 2: Query Warsaw events with geo radius
    test_warsaw_events(api_key)

    # Test 3: Query Kraków music events
    test_krakow_music(api_key)

    # Test 4: Get venue details
    test_venue_data(api_key)

    # Test 5: Get attraction/performer data
    test_attraction_data(api_key)

    # Test 6: Test pagination
    test_pagination(api_key)

    Logger.info("\n✅ All tests completed!")
  end

  defp test_basic_connection(api_key) do
    Logger.info("\n📍 Test 1: Basic Poland events query...")

    url = "#{@base_url}/events.json"
    params = [
      apikey: api_key,
      countryCode: "PL",
      size: 5
    ]

    case make_request(url, params) do
      {:ok, response} ->
        events = response["_embedded"]["events"] || []
        total = response["page"]["totalElements"] || 0

        Logger.info("✅ Success! Found #{total} total events in Poland")
        Logger.info("Sample events:")

        Enum.each(events, fn event ->
          Logger.info("  - #{event["name"]} (#{event["dates"]["start"]["localDate"] || "TBD"})")
          if event["_embedded"]["venues"] do
            venue = List.first(event["_embedded"]["venues"])
            Logger.info("    Venue: #{venue["name"]} in #{venue["city"]["name"]}")
          end
        end)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch Poland events: #{inspect(reason)}")
    end
  end

  defp test_warsaw_events(api_key) do
    Logger.info("\n📍 Test 2: Warsaw events within 50km radius...")

    url = "#{@base_url}/events.json"
    params = [
      apikey: api_key,
      latlong: "52.2297,21.0122",
      radius: 50,
      unit: "km",
      size: 5
    ]

    case make_request(url, params) do
      {:ok, response} ->
        events = response["_embedded"]["events"] || []
        total = response["page"]["totalElements"] || 0

        Logger.info("✅ Found #{total} events near Warsaw")

        Enum.each(events, fn event ->
          Logger.info("  - #{event["name"]}")
          if event["priceRanges"] do
            price = List.first(event["priceRanges"])
            Logger.info("    Price: #{price["min"]}-#{price["max"]} #{price["currency"]}")
          end
        end)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch Warsaw events: #{inspect(reason)}")
    end
  end

  defp test_krakow_music(api_key) do
    Logger.info("\n📍 Test 3: Kraków music events...")

    url = "#{@base_url}/events.json"
    params = [
      apikey: api_key,
      countryCode: "PL",
      city: "Kraków",
      classificationName: "music",
      size: 5
    ]

    case make_request(url, params) do
      {:ok, response} ->
        events = response["_embedded"]["events"] || []
        total = response["page"]["totalElements"] || 0

        Logger.info("✅ Found #{total} music events in Kraków")

        Enum.each(events, fn event ->
          Logger.info("  - #{event["name"]}")

          # Check for classifications
          if event["classifications"] do
            classification = List.first(event["classifications"])
            genre = classification["genre"]["name"] || "Unknown"
            Logger.info("    Genre: #{genre}")
          end
        end)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch Kraków music events: #{inspect(reason)}")
    end
  end

  defp test_venue_data(api_key) do
    Logger.info("\n📍 Test 4: Venue data retrieval...")

    url = "#{@base_url}/venues.json"
    params = [
      apikey: api_key,
      countryCode: "PL",
      size: 3
    ]

    case make_request(url, params) do
      {:ok, response} ->
        venues = response["_embedded"]["venues"] || []
        total = response["page"]["totalElements"] || 0

        Logger.info("✅ Found #{total} venues in Poland")

        Enum.each(venues, fn venue ->
          Logger.info("  - #{venue["name"]}")
          Logger.info("    City: #{venue["city"]["name"]}")

          if venue["location"] do
            Logger.info("    Coordinates: #{venue["location"]["latitude"]}, #{venue["location"]["longitude"]}")
          end

          if venue["address"] do
            Logger.info("    Address: #{venue["address"]["line1"]}")
          end
        end)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch venue data: #{inspect(reason)}")
    end
  end

  defp test_attraction_data(api_key) do
    Logger.info("\n📍 Test 5: Attraction/Performer data...")

    url = "#{@base_url}/attractions.json"
    params = [
      apikey: api_key,
      countryCode: "PL",
      size: 3
    ]

    case make_request(url, params) do
      {:ok, response} ->
        attractions = response["_embedded"]["attractions"] || []
        total = response["page"]["totalElements"] || 0

        Logger.info("✅ Found #{total} attractions/performers for Poland")

        Enum.each(attractions, fn attraction ->
          Logger.info("  - #{attraction["name"]}")

          if attraction["classifications"] do
            classification = List.first(attraction["classifications"])
            type = classification["segment"]["name"] || "Unknown"
            Logger.info("    Type: #{type}")
          end

          if attraction["externalLinks"] do
            Enum.each(attraction["externalLinks"], fn {platform, links} ->
              if is_list(links) && length(links) > 0 do
                link = List.first(links)
                Logger.info("    #{String.capitalize(platform)}: #{link["url"]}")
              end
            end)
          end
        end)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch attraction data: #{inspect(reason)}")
    end
  end

  defp test_pagination(api_key) do
    Logger.info("\n📍 Test 6: Pagination test...")

    # First page
    url = "#{@base_url}/events.json"
    params = [
      apikey: api_key,
      countryCode: "PL",
      size: 2,
      page: 0
    ]

    case make_request(url, params) do
      {:ok, response} ->
        page_info = response["page"]
        Logger.info("✅ Pagination info:")
        Logger.info("  - Current page: #{page_info["number"]}")
        Logger.info("  - Page size: #{page_info["size"]}")
        Logger.info("  - Total elements: #{page_info["totalElements"]}")
        Logger.info("  - Total pages: #{page_info["totalPages"]}")

        # Try to get second page
        if page_info["totalPages"] > 1 do
          params2 = Keyword.put(params, :page, 1)

          case make_request(url, params2) do
            {:ok, response2} ->
              Logger.info("  - Successfully fetched page 2")
              events = response2["_embedded"]["events"] || []
              Logger.info("  - Events on page 2: #{length(events)}")
            {:error, _} ->
              Logger.error("  - Failed to fetch page 2")
          end
        end

      {:error, reason} ->
        Logger.error("❌ Failed pagination test: #{inspect(reason)}")
    end
  end

  defp make_request(url, params) do
    client = Tesla.client([
      {Tesla.Middleware.BaseUrl, ""},
      {Tesla.Middleware.Query, params},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Timeout, timeout: 10_000}
    ])

    case Tesla.get(client, url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %Tesla.Env{status: 401}} ->
        {:error, "Authentication failed - check your API key"}
      {:ok, %Tesla.Env{status: 429}} ->
        {:error, "Rate limit exceeded"}
      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_msg = if is_map(body) && body["fault"],
          do: body["fault"]["faultstring"],
          else: "HTTP #{status}"
        {:error, error_msg}
      {:error, reason} ->
        {:error, reason}
    end
  end
end