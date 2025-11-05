defmodule EventasaurusDiscovery.Sources.Sortiraparis.TransformerTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Transformer

  describe "transform_event/2" do
    test "transforms single-date event successfully" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/319282-indochine",
        "article_id" => "319282",
        "title" => "Indochine Concert at Accor Arena",
        "date_string" => "October 31, 2025",
        "description" => "Indochine returns to Paris for an exclusive concert.",
        "image_url" => "https://www.sortiraparis.com/images/indochine.jpg",
        "is_ticketed" => true,
        "is_free" => false,
        "min_price" => Decimal.new("45"),
        "max_price" => Decimal.new("85"),
        "currency" => "EUR",
        "performers" => [],
        "venue" => %{
          "name" => "Accor Arena",
          "address" => "8 Boulevard de Bercy, 75012 Paris",
          "city" => "Paris",
          "postal_code" => "75012",
          "country" => "France"
        }
      }

      assert {:ok, events} = Transformer.transform_event(raw_event)
      assert length(events) == 1

      event = Enum.at(events, 0)
      # Use map access with atom keys
      # Day shifts due to timezone
      assert event[:external_id] =~ ~r/sortiraparis_319282_2025-10-3\d/
      assert event[:title] == "Indochine Concert at Accor Arena"
      assert event[:description] == "Indochine returns to Paris for an exclusive concert."
      assert event[:image_url] == "https://www.sortiraparis.com/images/indochine.jpg"
      assert event[:is_ticketed] == true
      assert event[:is_free] == false
      assert Decimal.equal?(event[:min_price], Decimal.new("45"))
      assert Decimal.equal?(event[:max_price], Decimal.new("85"))
      assert event[:currency] == "EUR"

      # Check venue_data (not venue)
      venue = event[:venue_data]
      assert venue[:name] == "Accor Arena"
      assert venue[:address] == "8 Boulevard de Bercy, 75012 Paris"
      assert venue[:city] == "Paris"
      assert venue[:country] == "France"

      # Check metadata
      assert event[:metadata][:article_id] == "319282"
      assert event[:source_url] =~ "sortiraparis.com"
    end

    test "transforms multi-date event into separate instances" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/320000-festival",
        "article_id" => "320000",
        "title" => "Summer Music Festival",
        "date_string" => "July 10, 12, 14, 2026",
        "description" => "Three-day music festival in Paris.",
        "image_url" => "https://www.sortiraparis.com/images/festival.jpg",
        "is_ticketed" => true,
        "is_free" => false,
        "min_price" => Decimal.new("50"),
        "max_price" => Decimal.new("120"),
        "currency" => "EUR",
        "performers" => [],
        "venue" => %{
          "name" => "Champ de Mars",
          "address" => "5 Avenue Anatole France, 75007 Paris",
          "city" => "Paris",
          "postal_code" => "75007",
          "country" => "France"
        }
      }

      assert {:ok, events} = Transformer.transform_event(raw_event)
      assert length(events) == 3

      # Check each event has unique external_id with date (accounting for timezone shift)
      external_ids = Enum.map(events, & &1[:external_id])
      # Days shift by 1 due to UTC conversion (Paris midnight = UTC 22:00 in July)
      assert "sortiraparis_320000_2026-07-09" in external_ids
      assert "sortiraparis_320000_2026-07-11" in external_ids
      assert "sortiraparis_320000_2026-07-13" in external_ids

      # All events should share same title and venue
      assert Enum.all?(events, &(&1[:title] == "Summer Music Festival"))
      assert Enum.all?(events, &(&1[:venue_data][:name] == "Champ de Mars"))

      # Each event should have correct starts_at date
      dates = Enum.map(events, & &1[:starts_at].day)
      assert 9 in dates
      assert 11 in dates
      assert 13 in dates
    end

    test "transforms date range event" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/320100-exhibition",
        "article_id" => "320100",
        "title" => "Art Exhibition",
        "date_string" => "September 1, 2025 to November 30, 2025",
        "description" => "Contemporary art exhibition.",
        "image_url" => "https://www.sortiraparis.com/images/art.jpg",
        "is_ticketed" => false,
        "is_free" => true,
        "min_price" => nil,
        "max_price" => nil,
        "currency" => "EUR",
        "performers" => [],
        "venue" => %{
          "name" => "Grand Palais",
          "address" => "3 Avenue du Général Eisenhower, 75008 Paris",
          "city" => "Paris",
          "postal_code" => "75008",
          "country" => "France"
        }
      }

      assert {:ok, events} = Transformer.transform_event(raw_event)
      assert length(events) == 2

      # Should have start and end dates (accounting for timezone shift)
      event = Enum.at(events, 0)
      assert event[:starts_at].month == 8 or event[:starts_at].month == 9

      end_event = Enum.at(events, 1)
      assert end_event[:starts_at].month == 11
    end

    test "handles free events correctly" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/320200-free-event",
        "article_id" => "320200",
        "title" => "Free Outdoor Concert",
        "date_string" => "August 15, 2025",
        "description" => "Free concert in the park.",
        "image_url" => nil,
        "is_ticketed" => false,
        "is_free" => true,
        "min_price" => nil,
        "max_price" => nil,
        "currency" => "EUR",
        "performers" => [],
        "venue" => %{
          "name" => "Parc de la Villette",
          "address" => "211 Avenue Jean Jaurès, 75019 Paris",
          "city" => "Paris",
          "postal_code" => "75019",
          "country" => "France"
        }
      }

      assert {:ok, [event]} = Transformer.transform_event(raw_event)
      assert event[:is_free] == true
      assert event[:is_ticketed] == false
      assert event[:min_price] == nil
      assert event[:max_price] == nil
    end

    test "handles events with performers" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/320300-concert",
        "article_id" => "320300",
        "title" => "Rock Concert",
        "date_string" => "June 20, 2025",
        "description" => "Amazing rock performance.",
        "image_url" => nil,
        "is_ticketed" => true,
        "is_free" => false,
        "min_price" => Decimal.new("35"),
        "max_price" => nil,
        "currency" => "EUR",
        "performers" => ["The Rolling Stones", "The Beatles"],
        "venue" => %{
          "name" => "Stade de France",
          "address" => "93200 Saint-Denis",
          "city" => "Saint-Denis",
          "postal_code" => "93200",
          "country" => "France"
        }
      }

      assert {:ok, [event]} = Transformer.transform_event(raw_event)
      assert event[:performers] == ["The Rolling Stones", "The Beatles"]
    end

    test "returns error when article_id missing" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/some-event",
        "title" => "Event Title",
        "date_string" => "October 31, 2025"
      }

      assert {:error, :missing_article_id} = Transformer.transform_event(raw_event)
    end

    test "returns error when title missing" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/123-event",
        "article_id" => "123",
        "date_string" => "October 31, 2025"
      }

      assert {:error, :missing_title} = Transformer.transform_event(raw_event)
    end

    test "returns error when date_string missing" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/123-event",
        "article_id" => "123",
        "title" => "Event Title"
      }

      assert {:error, :missing_dates} = Transformer.transform_event(raw_event)
    end

    test "returns error when venue missing" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/123-event",
        "article_id" => "123",
        "title" => "Event Title",
        "date_string" => "October 31, 2025"
      }

      assert {:error, :missing_venue} = Transformer.transform_event(raw_event)
    end

    test "returns error when date parsing fails" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/123-event",
        "article_id" => "123",
        "title" => "Event Title",
        "date_string" => "Invalid date format",
        "venue" => %{"name" => "Venue", "address" => "Address"}
      }

      assert {:error, :unsupported_date_format} = Transformer.transform_event(raw_event)
    end

    test "uses custom timezone option" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/123-event",
        "article_id" => "123",
        "title" => "Event Title",
        "date_string" => "October 31, 2025",
        "venue" => %{
          "name" => "Test Venue",
          "address" => "123 Test St",
          "city" => "Paris",
          "country" => "France"
        }
      }

      options = %{timezone: "America/New_York"}
      assert {:ok, [event]} = Transformer.transform_event(raw_event, options)
      # Verify timezone conversion worked (date should be different from Paris timezone)
      assert event[:starts_at].time_zone == "Etc/UTC"
    end

    test "preserves original date string in metadata" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/123-event",
        "article_id" => "123",
        "title" => "Event Title",
        "date_string" => "Friday, October 31, 2025",
        "original_date_string" => "Friday, October 31, 2025",
        "venue" => %{
          "name" => "Test Venue",
          "address" => "123 Test St",
          "city" => "Paris",
          "country" => "France"
        }
      }

      assert {:ok, [event]} = Transformer.transform_event(raw_event)
      assert event[:metadata][:original_date_string] == "Friday, October 31, 2025"
    end

    test "handles missing optional fields gracefully" do
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/123-event",
        "article_id" => "123",
        "title" => "Minimal Event",
        "date_string" => "October 31, 2025",
        "venue" => %{
          "name" => "Test Venue",
          "address" => "123 Test St",
          "city" => "Paris",
          "country" => "France"
        }
      }

      assert {:ok, [event]} = Transformer.transform_event(raw_event)
      assert event[:description] == nil
      assert event[:image_url] == nil
      assert event[:is_ticketed] == false
      assert event[:is_free] == false
      assert event[:min_price] == nil
      assert event[:max_price] == nil
    end

    test "handles DST fall-back ambiguous time correctly" do
      # October 26, 2025: Clocks fall back at 3am to 2am in Paris
      # This means 2:30am occurs twice - test we select first occurrence
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/123-dst-fallback",
        "article_id" => "123",
        "title" => "DST Fall-back Test",
        "date_string" => "October 26, 2025",
        "time_string" => "2h30",
        # Time that occurs twice during fall-back
        "venue" => %{
          "name" => "Test Venue",
          "address" => "123 Test St",
          "city" => "Paris",
          "country" => "France"
        }
      }

      # Should succeed without crashing and pick first occurrence
      assert {:ok, [event]} = Transformer.transform_event(raw_event)
      assert event[:starts_at].time_zone == "Etc/UTC"

      # Verify the time was processed (not midnight default)
      # First occurrence of 2:30am CEST = 00:30 UTC (before clocks fall back)
      # After clocks fall back, 2:30am CET = 01:30 UTC
      # We should get 00:30 UTC (first occurrence)
      assert event[:starts_at].hour == 0
      assert event[:starts_at].minute == 30
    end

    test "handles DST spring-forward gap time correctly" do
      # March 30, 2025: Clocks spring forward at 2am to 3am in Paris
      # This means 2:30am never exists - test we select time after gap
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/124-dst-gap",
        "article_id" => "124",
        "title" => "DST Spring-forward Test",
        "date_string" => "March 30, 2025",
        "time_string" => "2h30",
        # Time in the gap (doesn't exist)
        "venue" => %{
          "name" => "Test Venue",
          "address" => "123 Test St",
          "city" => "Paris",
          "country" => "France"
        }
      }

      # Should succeed without crashing and pick time after gap
      assert {:ok, [event]} = Transformer.transform_event(raw_event)
      assert event[:starts_at].time_zone == "Etc/UTC"

      # Verify the time was adjusted to after gap
      # 2:30am doesn't exist - clocks jump from 2am to 3am
      # After-gap time would be 3:30am CEST = 01:30 UTC
      assert event[:starts_at].hour == 1
      assert event[:starts_at].minute == 30
    end

    test "handles normal (non-DST-transition) time with time_string override" do
      # Regular day with no DST transition to verify normal behavior
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/125-normal",
        "article_id" => "125",
        "title" => "Normal Time Test",
        "date_string" => "June 15, 2025",
        "time_string" => "20h30",
        # 8:30pm - normal time
        "venue" => %{
          "name" => "Test Venue",
          "address" => "123 Test St",
          "city" => "Paris",
          "country" => "France"
        }
      }

      assert {:ok, [event]} = Transformer.transform_event(raw_event)
      assert event[:starts_at].time_zone == "Etc/UTC"

      # June 15 is during CEST (UTC+2), so 20:30 CEST = 18:30 UTC
      assert event[:starts_at].hour == 18
      assert event[:starts_at].minute == 30
    end

    test "handles time_string without minutes during DST transition" do
      # Test the French time parser fix with DST edge case
      raw_event = %{
        "url" => "https://www.sortiraparis.com/articles/126-dst-no-minutes",
        "article_id" => "126",
        "title" => "DST No Minutes Test",
        "date_string" => "October 26, 2025",
        "time_string" => "2h",
        # Hour only, no minutes, during DST fall-back
        "venue" => %{
          "name" => "Test Venue",
          "address" => "123 Test St",
          "city" => "Paris",
          "country" => "France"
        }
      }

      # Should parse "2h" correctly and handle DST ambiguity
      assert {:ok, [event]} = Transformer.transform_event(raw_event)
      assert event[:starts_at].time_zone == "Etc/UTC"

      # First occurrence of 2:00am CEST = 00:00 UTC
      assert event[:starts_at].hour == 0
      assert event[:starts_at].minute == 0
    end
  end
end
