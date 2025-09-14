defmodule Mix.Tasks.Scraper.TestDetail do
  @moduledoc """
  Test event detail page parser for Bandsintown.

  ## Usage

      # Test a specific event URL
      mix scraper.test_detail --url="https://www.bandsintown.com/e/107302000-florence-and-the-machine-at-tauron-arena"

      # Test with predefined test set
      mix scraper.test_detail --test-set

      # Save HTML for debugging
      mix scraper.test_detail --url="..." --save-html
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client
  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.DetailExtractor

  @shortdoc "Test Bandsintown event detail parser"

  # Predefined test URLs collected from actual Kraków results
  @test_urls [
    "https://www.bandsintown.com/e/107302000-florence-and-the-machine-at-tauron-arena",
    "https://www.bandsintown.com/e/107051909-iconito-at-obecny-urad-zubrohlava",
    "https://www.bandsintown.com/e/1034843304-avi-kaplan-at-klub-kwadrat",
    "https://www.bandsintown.com/e/107331384-renata-przemyk-at-culture-and-promotion-center",
    "https://www.bandsintown.com/e/107285584-bulgar-at-chicago-jazz-live-music"
  ]

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} = OptionParser.parse(args,
      strict: [
        url: :string,
        test_set: :boolean,
        save_html: :boolean,
        verbose: :boolean
      ]
    )

    cond do
      opts[:test_set] ->
        test_multiple_urls(@test_urls, opts)

      url = opts[:url] ->
        test_single_url(url, opts)

      true ->
        Logger.error("Please provide --url or use --test-set")
        print_usage()
    end
  end

  defp test_single_url(url, opts) do
    Logger.info("""

    =====================================
    🎵 Testing Event Detail Parser
    =====================================
    URL: #{url}
    =====================================
    """)

    # Fetch the page
    case Client.fetch_event_page(url) do
      {:ok, html} ->
        if opts[:save_html] do
          save_html(url, html)
        end

        # Parse the page
        {:ok, event_data} = DetailExtractor.extract_event_details(html, url)
        display_parsed_data(event_data, opts[:verbose])
        {:ok, event_data}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp test_multiple_urls(urls, opts) do
    Logger.info("""

    =====================================
    🎵 Testing Multiple Event URLs
    =====================================
    Testing #{length(urls)} events
    =====================================
    """)

    results = urls
    |> Enum.with_index(1)
    |> Enum.map(fn {url, index} ->
      Logger.info("""

      -------------------------------------
      Event #{index}/#{length(urls)}
      -------------------------------------
      """)

      result = test_single_url(url, opts)

      # Add delay between requests
      if index < length(urls) do
        Process.sleep(3000)
      end

      {url, result}
    end)

    # Summary
    display_summary(results)
  end

  defp display_parsed_data(data, verbose) do
    Logger.info("""

    ✅ Successfully Parsed Event Details
    =====================================

    🎤 ARTIST INFORMATION
    ---------------------
    Artist: #{data["artist_name"] || "NOT FOUND"}
    Artist URL: #{data["artist_url"] || "N/A"}
    Genre: #{data["genre"] || "N/A"}
    Tags: #{inspect(data["tags"] || [])}

    📍 VENUE INFORMATION
    --------------------
    Venue: #{data["venue_name"] || "NOT FOUND"}
    Address: #{data["venue_address"] || "N/A"}
    City: #{data["venue_city"] || "N/A"}
    Region: #{data["venue_region"] || "N/A"}
    Country: #{data["venue_country"] || "N/A"}
    Postal Code: #{data["venue_postal_code"] || "N/A"}
    Coordinates: (#{data["venue_latitude"] || "?"}, #{data["venue_longitude"] || "?"})

    📅 EVENT DETAILS
    ----------------
    Title: #{data["title"] || "N/A"}
    Date/Time: #{data["date"] || "NOT FOUND"}
    End Date: #{data["end_date"] || "N/A"}
    Status: #{data["event_status"] || "N/A"}
    Description: #{truncate_text(data["description"], 200)}

    🎫 TICKET INFORMATION
    ---------------------
    Ticket URL: #{data["ticket_url"] || "N/A"}
    Price Range: #{format_price_range(data)}
    Availability: #{data["availability"] || "N/A"}

    📊 ENGAGEMENT
    -------------
    RSVP Count: #{data["rsvp_count"] || "N/A"}
    Interested: #{data["interested_count"] || "N/A"}

    🖼️ MEDIA
    --------
    Image URL: #{data["image_url"] || "N/A"}

    🔗 SOCIAL MEDIA
    ---------------
    Facebook Event: #{data["facebook_event"] || "N/A"}
    Other Links: #{inspect(data["artist_same_as"] || [])}
    """)

    if verbose do
      Logger.info("""

      📝 FULL DATA DUMP
      -----------------
      #{inspect(data, pretty: true, limit: :infinity)}
      """)
    end
  end

  defp display_summary(results) do
    successful = Enum.count(results, fn {_, result} ->
      match?({:ok, _}, result)
    end)

    failed = length(results) - successful

    Logger.info("""

    =====================================
    📊 PARSING SUMMARY
    =====================================
    Total Events: #{length(results)}
    Successful: #{successful}
    Failed: #{failed}
    Success Rate: #{round(successful / length(results) * 100)}%
    =====================================
    """)

    # Show which fields were successfully parsed
    if successful > 0 do
      field_stats = calculate_field_statistics(results)
      display_field_statistics(field_stats)
    end

    # List failed URLs
    if failed > 0 do
      Logger.error("❌ Failed URLs:")
      results
      |> Enum.filter(fn {_, result} -> match?({:error, _}, result) end)
      |> Enum.each(fn {url, _} ->
        Logger.error("  - #{url}")
      end)
    end
  end

  defp calculate_field_statistics(results) do
    successful_results = results
    |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
    |> Enum.map(fn {_, {:ok, data}} -> data end)

    fields = [
      "artist_name", "venue_name", "date", "venue_address", "venue_city",
      "venue_latitude", "venue_longitude", "ticket_url", "min_price",
      "max_price", "description", "image_url", "rsvp_count", "genre"
    ]

    Enum.map(fields, fn field ->
      count = Enum.count(successful_results, fn data ->
        data[field] != nil && data[field] != ""
      end)
      percentage = round(count / length(successful_results) * 100)
      {field, count, percentage}
    end)
  end

  defp display_field_statistics(stats) do
    Logger.info("""

    📈 FIELD EXTRACTION SUCCESS RATES
    ----------------------------------
    """)

    Enum.each(stats, fn {field, count, percentage} ->
      status = cond do
        percentage == 100 -> "✅"
        percentage >= 80 -> "🟨"
        percentage >= 50 -> "🟧"
        true -> "❌"
      end

      Logger.info("#{status} #{String.pad_trailing(field, 20)} #{percentage}% (#{count} events)")
    end)
  end

  defp format_price_range(data) do
    min = data["min_price"]
    max = data["max_price"]
    currency = data["currency"] || "USD"

    cond do
      min && max -> "#{currency} #{min} - #{max}"
      min -> "#{currency} #{min}+"
      max -> "Up to #{currency} #{max}"
      true -> "N/A"
    end
  end

  defp truncate_text(nil, _), do: "N/A"
  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp save_html(url, html) do
    # Extract event ID from URL
    event_id = case Regex.run(~r/\/e\/(\d+)/, url) do
      [_, id] -> id
      _ -> "unknown"
    end

    filename = "test_data/bandsintown_event_#{event_id}.html"
    File.mkdir_p!("test_data")
    File.write!(filename, html)

    Logger.info("💾 Saved HTML to #{filename}")
  end

  defp print_usage do
    Logger.info("""

    Usage:
      mix scraper.test_detail --url="https://www.bandsintown.com/e/..."
      mix scraper.test_detail --test-set
      mix scraper.test_detail --url="..." --save-html --verbose
    """)
  end
end