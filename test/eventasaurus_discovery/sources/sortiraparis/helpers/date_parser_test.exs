defmodule EventasaurusDiscovery.Sources.Sortiraparis.Helpers.DateParserTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Helpers.DateParser

  describe "parse_dates/2" do
    test "parses multi-date list format" do
      assert {:ok, dates} = DateParser.parse_dates("February 25, 27, 28, 2026")
      assert length(dates) == 3
      assert Enum.at(dates, 0) == ~U[2026-02-24 23:00:00Z]  # Paris midnight = UTC 23:00 (winter)
      assert Enum.at(dates, 1) == ~U[2026-02-26 23:00:00Z]
      assert Enum.at(dates, 2) == ~U[2026-02-27 23:00:00Z]
    end

    test "parses date range format" do
      assert {:ok, dates} = DateParser.parse_dates("October 15, 2025 to January 19, 2026")
      assert length(dates) == 2
      # Verify dates are in October and January (accounting for UTC conversion)
      assert Enum.at(dates, 0).year == 2025
      assert Enum.at(dates, 0).month == 10
      assert Enum.at(dates, 1).year == 2026
      assert Enum.at(dates, 1).month == 1
    end

    test "parses single date with day name" do
      assert {:ok, dates} = DateParser.parse_dates("Friday, October 31, 2025")
      assert length(dates) == 1
      assert Enum.at(dates, 0) == ~U[2025-10-30 23:00:00Z]
    end

    test "parses single date without day name" do
      assert {:ok, dates} = DateParser.parse_dates("December 25, 2025")
      assert length(dates) == 1
      assert Enum.at(dates, 0) == ~U[2025-12-24 23:00:00Z]
    end

    test "parses date with time" do
      assert {:ok, dates} = DateParser.parse_dates("Saturday October 11 at 12 noon")
      assert length(dates) == 1
      # Time should be 12:00 Paris = 10:00 UTC (summer time)
      date = Enum.at(dates, 0)
      assert date.hour == 10
      assert date.minute == 0
    end

    test "returns error for invalid input" do
      assert {:error, :invalid_input} = DateParser.parse_dates(nil)
      assert {:error, :invalid_input} = DateParser.parse_dates(123)
    end

    test "returns error for unsupported date format" do
      assert {:error, :unsupported_date_format} = DateParser.parse_dates("Invalid date string")
    end

    test "handles custom timezone option" do
      options = %{timezone: "America/New_York"}
      assert {:ok, dates} = DateParser.parse_dates("October 31, 2025", options)
      assert length(dates) == 1
      # Verify it's converted to UTC from New York timezone
      date = Enum.at(dates, 0)
      assert date.time_zone == "Etc/UTC"
    end

    test "handles custom default year option" do
      options = %{default_year: 2027}
      assert {:ok, dates} = DateParser.parse_dates("Saturday October 11 at 12 noon", options)
      date = Enum.at(dates, 0)
      assert date.year == 2027
    end
  end

  describe "parse_multi_date_list/2" do
    test "parses February multi-date list" do
      dates = DateParser.parse_multi_date_list("February 25, 27, 28, 2026", %{})
      assert length(dates) == 3
      assert Enum.all?(dates, &(&1.month == 2))
      assert Enum.all?(dates, &(&1.year == 2026))
    end

    test "parses October multi-date list" do
      dates = DateParser.parse_multi_date_list("October 11, 12, 13, 2025", %{})
      assert length(dates) == 3
      # Days shift by 1 due to UTC conversion (Paris midnight = UTC 22:00 in October)
      assert Enum.at(dates, 0).day == 10
      assert Enum.at(dates, 1).day == 11
      assert Enum.at(dates, 2).day == 12
    end

    test "parses multi-date with many dates" do
      dates = DateParser.parse_multi_date_list("July 1, 3, 5, 7, 9, 2026", %{})
      assert length(dates) == 5
      # Days shift by 1 due to UTC conversion (Paris midnight = UTC 22:00 in July)
      assert Enum.map(dates, & &1.day) == [30, 2, 4, 6, 8]
    end

    test "returns nil for non-matching pattern" do
      assert nil == DateParser.parse_multi_date_list("Invalid format", %{})
    end

    test "handles single date in multi-date format" do
      dates = DateParser.parse_multi_date_list("August 15, 2025", %{})
      assert length(dates) == 1
      # Day shifts by 1 due to UTC conversion (Paris midnight = UTC 22:00 in August)
      assert Enum.at(dates, 0).day == 14
    end
  end

  describe "parse_date_range/2" do
    test "parses range within same year" do
      dates = DateParser.parse_date_range("June 15, 2025 to August 31, 2025", %{})
      assert length(dates) == 2
      assert Enum.at(dates, 0).month == 6
      assert Enum.at(dates, 1).month == 8
      assert Enum.all?(dates, &(&1.year == 2025))
    end

    test "parses range across years" do
      dates = DateParser.parse_date_range("December 20, 2025 to January 10, 2026", %{})
      assert length(dates) == 2
      assert Enum.at(dates, 0).year == 2025
      assert Enum.at(dates, 1).year == 2026
    end

    test "returns nil for non-matching pattern" do
      assert nil == DateParser.parse_date_range("Not a range", %{})
    end

    test "returns nil for invalid dates in range" do
      # Invalid day of month
      assert nil == DateParser.parse_date_range("February 30, 2025 to March 1, 2025", %{})
    end
  end

  describe "parse_single_date/2" do
    test "parses date with day name" do
      date = DateParser.parse_single_date("Monday, March 17, 2025", %{})
      assert date.year == 2025
      assert date.month == 3
      # Day shifts by 1 due to UTC conversion (Paris midnight = UTC 23:00 in March)
      assert date.day == 16
    end

    test "parses date without day name" do
      date = DateParser.parse_single_date("April 22, 2026", %{})
      assert date.year == 2026
      assert date.month == 4
      # Day shifts by 1 due to UTC conversion (Paris midnight = UTC 22:00 in April)
      assert date.day == 21
    end

    test "handles all month names" do
      months = [
        {"January", 1},
        {"February", 2},
        {"March", 3},
        {"April", 4},
        {"May", 5},
        {"June", 6},
        {"July", 7},
        {"August", 8},
        {"September", 9},
        {"October", 10},
        {"November", 11},
        {"December", 12}
      ]

      Enum.each(months, fn {month_name, month_num} ->
        date = DateParser.parse_single_date("#{month_name} 15, 2025", %{})
        assert date.month == month_num
      end)
    end

    test "returns nil for invalid pattern" do
      assert nil == DateParser.parse_single_date("Invalid date", %{})
    end

    test "returns nil for invalid date values" do
      # February 30 doesn't exist
      assert nil == DateParser.parse_single_date("February 30, 2025", %{})
    end
  end

  describe "parse_date_with_time/2" do
    test "parses date with hour" do
      date = DateParser.parse_date_with_time("October 11 at 12 noon", %{default_year: 2025})
      assert date.month == 10
      assert date.day == 11
      assert date.hour == 10  # 12:00 Paris = 10:00 UTC in summer
    end

    test "parses date with hour and minute" do
      date = DateParser.parse_date_with_time("October 11 at 14:30", %{default_year: 2025})
      assert date.hour == 12  # 14:30 Paris = 12:30 UTC in summer
      assert date.minute == 30
    end

    test "parses date with PM modifier" do
      date = DateParser.parse_date_with_time("October 11 at 3 pm", %{default_year: 2025})
      assert date.hour == 13  # 15:00 Paris = 13:00 UTC in summer
    end

    test "parses date with AM modifier" do
      date = DateParser.parse_date_with_time("October 11 at 9 am", %{default_year: 2025})
      assert date.hour == 7  # 09:00 Paris = 07:00 UTC in summer
    end

    test "parses noon modifier" do
      date = DateParser.parse_date_with_time("October 11 at 12 noon", %{default_year: 2025})
      assert date.hour == 10  # 12:00 Paris = 10:00 UTC in summer
    end

    test "handles 12 AM as midnight" do
      date = DateParser.parse_date_with_time("October 11 at 12 am", %{default_year: 2025})
      assert date.hour == 22  # 00:00 Paris = 22:00 UTC previous day in summer
    end

    test "uses default year when not specified" do
      current_year = DateTime.utc_now().year
      date = DateParser.parse_date_with_time("October 11 at 10:00", %{})
      assert date.year == current_year
    end

    test "handles day name in date with time" do
      date = DateParser.parse_date_with_time("Saturday October 11 at 20:00", %{default_year: 2025})
      assert date.month == 10
      assert date.day == 11
      assert date.hour == 18  # 20:00 Paris = 18:00 UTC in summer
    end

    test "returns nil for invalid pattern" do
      assert nil == DateParser.parse_date_with_time("Not a valid time", %{})
    end
  end
end
