defmodule EventasaurusDiscovery.Sources.Kupbilecik.TransformerTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Kupbilecik.Transformer

  describe "parse_polish_date/1" do
    test "parses date with 'o godz.' format" do
      date_string = "7 grudnia 2025 o godz. 20:00"

      assert {:ok, datetime} = Transformer.parse_polish_date(date_string)
      assert datetime.year == 2025
      assert datetime.month == 12
      assert datetime.day == 7
      assert datetime.hour == 20
      assert datetime.minute == 0
    end

    test "parses date with comma time format" do
      date_string = "15 maja 2025, 19:30"

      assert {:ok, datetime} = Transformer.parse_polish_date(date_string)
      assert datetime.year == 2025
      assert datetime.month == 5
      assert datetime.day == 15
      assert datetime.hour == 19
      assert datetime.minute == 30
    end

    test "parses date-only format" do
      date_string = "1 stycznia 2025"

      assert {:ok, datetime} = Transformer.parse_polish_date(date_string)
      assert datetime.year == 2025
      assert datetime.month == 1
      assert datetime.day == 1
      assert datetime.hour == 0
      assert datetime.minute == 0
    end

    test "handles all Polish months" do
      months = [
        {"1 stycznia 2025", 1},
        {"2 lutego 2025", 2},
        {"3 marca 2025", 3},
        {"4 kwietnia 2025", 4},
        {"5 maja 2025", 5},
        {"6 czerwca 2025", 6},
        {"7 lipca 2025", 7},
        {"8 sierpnia 2025", 8},
        {"9 września 2025", 9},
        {"10 października 2025", 10},
        {"11 listopada 2025", 11},
        {"12 grudnia 2025", 12}
      ]

      for {date_string, expected_month} <- months do
        assert {:ok, datetime} = Transformer.parse_polish_date(date_string),
               "Failed for: #{date_string}"

        assert datetime.month == expected_month
      end
    end

    test "is case-insensitive" do
      date_string = "7 GRUDNIA 2025 O GODZ. 20:00"

      assert {:ok, datetime} = Transformer.parse_polish_date(date_string)
      assert datetime.month == 12
    end

    test "handles whitespace variations" do
      date_string = "  7  grudnia  2025  o  godz.  20:00  "

      assert {:ok, datetime} = Transformer.parse_polish_date(date_string)
      assert datetime.year == 2025
    end

    test "returns error for invalid date format" do
      assert {:error, {:invalid_date_format, _}} = Transformer.parse_polish_date("invalid date")
    end

    test "returns error for nil" do
      assert {:error, :date_is_nil} = Transformer.parse_polish_date(nil)
    end

    test "returns error for unknown month" do
      # When the regex matches but month name isn't in polish_months map,
      # we get :unknown_month error. Use a valid word pattern (letters only).
      # Note: the code lowercases input, so we check for lowercase in error
      assert {:error, {:unknown_month, "fakemonth"}} =
               Transformer.parse_polish_date("7 fakemonth 2025")
    end

    test "returns error for invalid format with underscores" do
      # Underscores in month name won't match the letter-only regex
      assert {:error, {:invalid_date_format, _}} =
               Transformer.parse_polish_date("7 unknown_month 2025")
    end
  end

  describe "transform_events/1" do
    test "transforms valid raw event successfully" do
      raw_events = [
        %{
          "event_id" => "186000",
          "title" => "Koncert Rockowy",
          "date_string" => "7 grudnia 2025 o godz. 20:00",
          "url" => "https://www.kupbilecik.pl/imprezy/186000/koncert-rockowy",
          "description" => "Niesamowity koncert",
          "image_url" => "https://example.com/image.jpg",
          "venue_name" => "Hala Sportowa",
          "address" => "ul. Sportowa 1",
          "city" => "Warszawa",
          "price" => "od 99 zł",
          "category" => "koncerty"
        }
      ]

      assert {:ok, [event]} = Transformer.transform_events(raw_events)

      assert event.external_id == "kupbilecik_event_186000_2025-12-07"
      assert event.title == "Koncert Rockowy"
      assert event.description_translations == %{"pl" => "Niesamowity koncert"}
      assert event.source_url == "https://www.kupbilecik.pl/imprezy/186000/koncert-rockowy"
      assert event.image_url == "https://example.com/image.jpg"
      assert event.starts_at.year == 2025
      assert event.starts_at.month == 12
      assert event.starts_at.day == 7
      assert event.starts_at.hour == 20
      assert event.venue_data.name == "Hala Sportowa"
      assert event.venue_data.address == "ul. Sportowa 1"
      assert event.venue_data.city == "Warszawa"
      assert event.venue_data.country == "Poland"
      assert event.price_info == "od 99 zł"
      assert event.category == "music"
    end

    test "transforms event with minimal fields" do
      raw_events = [
        %{
          "event_id" => "123",
          "title" => "Minimal Event",
          "date_string" => "1 stycznia 2025"
        }
      ]

      assert {:ok, [event]} = Transformer.transform_events(raw_events)

      assert event.external_id == "kupbilecik_event_123_2025-01-01"
      assert event.title == "Minimal Event"
      assert event.starts_at.year == 2025
    end

    test "filters out events without dates" do
      raw_events = [
        %{
          "event_id" => "valid",
          "title" => "Valid Event",
          "date_string" => "1 stycznia 2025"
        },
        %{
          "event_id" => "invalid",
          "title" => "No Date Event"
        }
      ]

      assert {:ok, events} = Transformer.transform_events(raw_events)
      assert length(events) == 1
      assert hd(events).title == "Valid Event"
    end

    test "filters out events without event_id" do
      raw_events = [
        %{
          "title" => "No ID Event",
          "date_string" => "1 stycznia 2025"
        }
      ]

      assert {:ok, events} = Transformer.transform_events(raw_events)
      assert events == []
    end

    test "calculates ends_at as 2 hours after starts_at by default" do
      raw_events = [
        %{
          "event_id" => "123",
          "title" => "Test Event",
          "date_string" => "1 stycznia 2025 o godz. 20:00"
        }
      ]

      assert {:ok, [event]} = Transformer.transform_events(raw_events)

      assert event.starts_at.hour == 20
      assert event.ends_at.hour == 22
    end
  end

  describe "transform_event/1" do
    test "builds correct external ID format with date" do
      raw_event = %{
        "event_id" => "abc123",
        "title" => "Test Event",
        "date_string" => "15 marca 2025"
      }

      [event] = Transformer.transform_event(raw_event)

      assert event.external_id == "kupbilecik_event_abc123_2025-03-15"
    end

    test "uses title or name for event title" do
      raw_event1 = %{
        "event_id" => "1",
        "title" => "Title Field",
        "date_string" => "1 stycznia 2025"
      }

      raw_event2 = %{
        "event_id" => "2",
        "name" => "Name Field",
        "date_string" => "1 stycznia 2025"
      }

      [event1] = Transformer.transform_event(raw_event1)
      [event2] = Transformer.transform_event(raw_event2)

      assert event1.title == "Title Field"
      assert event2.title == "Name Field"
    end

    test "maps Polish categories to canonical categories" do
      test_cases = [
        {"koncerty", "music"},
        {"spektakle", "theatre"},
        {"festiwale", "festival"},
        {"muzyka", "music"},
        {"teatr", "theatre"}
      ]

      for {polish_category, expected_canonical} <- test_cases do
        raw_event = %{
          "event_id" => "1",
          "title" => "Test",
          "date_string" => "1 stycznia 2025",
          "category" => polish_category
        }

        [event] = Transformer.transform_event(raw_event)
        assert event.category == expected_canonical, "Failed for: #{polish_category}"
      end
    end

    test "uses 'other' for unknown categories" do
      raw_event = %{
        "event_id" => "1",
        "title" => "Test",
        "date_string" => "1 stycznia 2025",
        "category" => "unknown_category"
      }

      [event] = Transformer.transform_event(raw_event)
      assert event.category == "other"
    end
  end

  describe "parse_price/1" do
    test "parses 'od XX zł' format" do
      {min, max} = Transformer.parse_price("od 55 zł")
      assert Decimal.equal?(min, Decimal.new("55"))
      assert Decimal.equal?(max, Decimal.new("55"))
    end

    test "parses range format 'XX-YY zł'" do
      {min, max} = Transformer.parse_price("40-55 zł")
      assert Decimal.equal?(min, Decimal.new("40"))
      assert Decimal.equal?(max, Decimal.new("55"))
    end

    test "parses simple 'XX zł' format" do
      {min, max} = Transformer.parse_price("99 zł")
      assert Decimal.equal?(min, Decimal.new("99"))
      assert Decimal.equal?(max, Decimal.new("99"))
    end

    test "parses PLN format" do
      {min, max} = Transformer.parse_price("120 PLN")
      assert Decimal.equal?(min, Decimal.new("120"))
      assert Decimal.equal?(max, Decimal.new("120"))
    end

    test "handles decimal prices with comma" do
      {min, max} = Transformer.parse_price("od 55,50 zł")
      assert Decimal.equal?(min, Decimal.new("55.50"))
      assert Decimal.equal?(max, Decimal.new("55.50"))
    end

    test "handles decimal prices with dot" do
      {min, max} = Transformer.parse_price("od 55.50 zł")
      assert Decimal.equal?(min, Decimal.new("55.50"))
      assert Decimal.equal?(max, Decimal.new("55.50"))
    end

    test "returns nil for nil input" do
      assert {nil, nil} = Transformer.parse_price(nil)
    end

    test "returns nil for empty string" do
      assert {nil, nil} = Transformer.parse_price("")
    end

    test "returns nil for unparseable string" do
      assert {nil, nil} = Transformer.parse_price("free admission")
    end

    test "transform_event includes min_price and max_price" do
      raw_event = %{
        "event_id" => "123",
        "title" => "Test Event",
        "date_string" => "1 stycznia 2025",
        "price" => "40-80 zł"
      }

      [event] = Transformer.transform_event(raw_event)
      assert Decimal.equal?(event.min_price, Decimal.new("40"))
      assert Decimal.equal?(event.max_price, Decimal.new("80"))
    end
  end
end
