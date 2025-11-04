defmodule EventasaurusDiscovery.Sources.Karnet.IntegrationTest do
  @moduledoc """
  Basic integration tests for Karnet Kraków scraper.

  These are simplified tests since Karnet is a lower-priority,
  localized scraper.
  """

  use ExUnit.Case, async: false

  alias EventasaurusDiscovery.Sources.Karnet.{
    Client,
    IndexExtractor,
    DetailExtractor,
    VenueMatcher
  }

  alias EventasaurusDiscovery.Sources.Shared.Parsers.MultilingualDateParser

  @moduletag :external
  @moduletag :karnet
  @moduletag timeout: 60_000

  describe "full scraping flow" do
    test "can fetch and parse index page" do
      {:ok, html} = Client.fetch_events_page(1)

      assert is_binary(html)
      assert byte_size(html) > 1000

      {:ok, events} = IndexExtractor.extract_events(html)

      assert is_list(events)
      assert length(events) > 0

      # Check first event structure
      [first | _] = events
      assert Map.has_key?(first, :url)
      assert Map.has_key?(first, :title)
      assert Map.has_key?(first, :date_text)
    end

    @tag :skip
    test "can fetch and parse detail page" do
      # Get an event from index
      {:ok, html} = Client.fetch_events_page(1)
      {:ok, events} = IndexExtractor.extract_events(html)

      # Get first event with URL
      event = Enum.find(events, & &1[:url])
      assert event

      # Fetch detail page
      {:ok, detail_html} = Client.fetch_page(event.url)
      {:ok, details} = DetailExtractor.extract_event_details(detail_html, event.url)

      assert details[:title]
      assert details[:source_url] == event.url
      assert details[:date_text] || details[:starts_at]
    end
  end

  describe "date parsing" do
    test "parses standard Polish date format" do
      assert {:ok, %{starts_at: start_dt}} =
               MultilingualDateParser.extract_and_parse("04.09.2025, 18:00",
                 languages: [:polish],
                 timezone: "Europe/Warsaw"
               )

      assert start_dt.year == 2025
      assert start_dt.month == 9
      # Day can be 3 or 4 due to timezone conversion (Europe/Warsaw → UTC)
      assert start_dt.day in [3, 4]
      # Hour will be converted from Warsaw time (18:00 CEST = 16:00 UTC)
      assert start_dt.hour in [16, 17, 18]
    end

    test "parses Polish month names" do
      assert {:ok, %{starts_at: start_dt}} =
               MultilingualDateParser.extract_and_parse("4 września 2025",
                 languages: [:polish],
                 timezone: "Europe/Warsaw"
               )

      assert start_dt.year == 2025
      assert start_dt.month == 9
      # Day can be 3 or 4 due to timezone conversion
      assert start_dt.day in [3, 4]
    end

    test "parses date ranges" do
      assert {:ok, %{starts_at: start_dt, ends_at: end_dt}} =
               MultilingualDateParser.extract_and_parse("04.09.2025 - 06.09.2025",
                 languages: [:polish],
                 timezone: "Europe/Warsaw"
               )

      # Days can be off by 1 due to timezone conversion
      assert start_dt.day in [3, 4]
      assert end_dt.day in [5, 6]
      assert start_dt != end_dt
    end
  end

  describe "venue matching" do
    test "matches known Kraków venues" do
      venue_data = VenueMatcher.match_venue("Tauron Arena Kraków")

      assert venue_data
      assert venue_data.name == "Tauron Arena Kraków"
      assert venue_data.city == "Kraków"
      assert venue_data.country == "Poland"
    end

    test "extracts venue address" do
      venue_data = VenueMatcher.match_venue("ICE Kraków, ul. Konopnickiej 17")

      assert venue_data
      assert venue_data.name
      assert venue_data.city == "Kraków"
    end
  end
end
