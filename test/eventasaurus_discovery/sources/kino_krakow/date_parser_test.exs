defmodule EventasaurusDiscovery.Sources.KinoKrakow.DateParserTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.KinoKrakow.DateParser

  describe "parse_date/1" do
    test "parses date with day name and month name" do
      # "środa, 1 października" (Wednesday, October 1)
      # Uses current year if not specified
      date_str = "środa, 1 października"
      result = DateParser.parse_date(date_str)

      assert result.month == 10
      assert result.day == 1
    end

    test "parses date with explicit year" do
      date_str = "15 marca 2025"

      assert ~D[2025-03-15] = DateParser.parse_date(date_str)
    end

    test "parses date without day name" do
      date_str = "15 marca 2025"

      assert ~D[2025-03-15] = DateParser.parse_date(date_str)
    end

    test "handles all Polish month names" do
      months = [
        {"1 stycznia 2025", ~D[2025-01-01]},
        {"5 lutego 2025", ~D[2025-02-05]},
        {"10 marca 2025", ~D[2025-03-10]},
        {"15 kwietnia 2025", ~D[2025-04-15]},
        {"20 maja 2025", ~D[2025-05-20]},
        {"25 czerwca 2025", ~D[2025-06-25]},
        {"30 lipca 2025", ~D[2025-07-30]},
        {"5 sierpnia 2025", ~D[2025-08-05]},
        {"10 września 2025", ~D[2025-09-10]},
        {"15 października 2025", ~D[2025-10-15]},
        {"20 listopada 2025", ~D[2025-11-20]},
        {"25 grudnia 2025", ~D[2025-12-25]}
      ]

      for {date_str, expected_date} <- months do
        assert ^expected_date = DateParser.parse_date(date_str)
      end
    end

    test "returns nil for invalid month name" do
      assert nil == DateParser.parse_date("1 InvalidMonth")
    end

    test "returns nil for unparseable format" do
      assert nil == DateParser.parse_date("not a date")
    end

    test "handles dates with extra whitespace" do
      date_str = "  środa,  1  października  2025  "

      assert ~D[2025-10-01] = DateParser.parse_date(date_str)
    end

    test "uses current year when year not specified" do
      current_year = Date.utc_today().year
      date_str = "15 marca"
      result = DateParser.parse_date(date_str)

      assert result.year == current_year
      assert result.month == 3
      assert result.day == 15
    end
  end

  describe "parse_time/1" do
    test "parses standard time format HH:MM" do
      assert %Time{hour: 14, minute: 30, second: 0} = DateParser.parse_time("14:30")
      assert %Time{hour: 9, minute: 0, second: 0} = DateParser.parse_time("09:00")
      assert %Time{hour: 23, minute: 59, second: 0} = DateParser.parse_time("23:59")
    end

    test "returns nil for invalid time format" do
      assert nil == DateParser.parse_time("not a time")
    end

    test "handles time with whitespace" do
      assert %Time{hour: 14, minute: 30} = DateParser.parse_time("  14:30  ")
    end

    test "handles single digit hours and minutes" do
      assert %Time{hour: 9, minute: 5, second: 0} = DateParser.parse_time("9:5")
    end
  end

  describe "parse_datetime/2" do
    test "combines date and time strings into UTC DateTime" do
      date_str = "1 października 2025"
      time_str = "14:30"

      datetime = DateParser.parse_datetime(date_str, time_str)

      # Should be converted to UTC
      assert datetime.time_zone == "Etc/UTC"
      assert datetime.year == 2025
      assert datetime.month == 10
      assert datetime.day == 1
    end

    test "returns nil when date parsing fails" do
      assert nil == DateParser.parse_datetime("invalid date", "14:30")
    end

    test "returns nil when time parsing fails" do
      assert nil == DateParser.parse_datetime("1 stycznia 2025", "invalid")
    end

    test "handles complete workflow with Polish date" do
      # Real-world example
      date_str = "piątek, 15 marca 2025"  # Friday, March 15
      time_str = "19:45"

      datetime = DateParser.parse_datetime(date_str, time_str)

      assert datetime.year == 2025
      assert datetime.month == 3
      assert datetime.day == 15
      # Time will be converted from Warsaw to UTC
      assert datetime.time_zone == "Etc/UTC"
    end

    test "handles timezone conversion correctly" do
      # Winter time example (UTC+1)
      date_str = "15 stycznia 2025"
      time_str = "14:00"

      datetime = DateParser.parse_datetime(date_str, time_str)

      # 14:00 CET (UTC+1) should be 13:00 UTC
      assert datetime.hour == 13
      assert datetime.minute == 0
    end

    test "handles summer time example (UTC+2)" do
      # Summer time example (UTC+2)
      date_str = "15 lipca 2025"
      time_str = "14:00"

      datetime = DateParser.parse_datetime(date_str, time_str)

      # 14:00 CEST (UTC+2) should be 12:00 UTC
      assert datetime.hour == 12
      assert datetime.minute == 0
    end
  end
end
