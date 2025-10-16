defmodule EventasaurusDiscovery.Sources.Quizmeisters.Helpers.TimeParserTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Quizmeisters.Helpers.TimeParser

  describe "parse_time_text/1" do
    test "parses 'Wednesdays at 7pm'" do
      assert {:ok, {:wednesday, ~T[19:00:00]}} = TimeParser.parse_time_text("Wednesdays at 7pm")
    end

    test "parses 'Thursdays at 8:00 PM'" do
      assert {:ok, {:thursday, ~T[20:00:00]}} = TimeParser.parse_time_text("Thursdays at 8:00 PM")
    end

    test "parses 'Tuesdays at 7:30pm'" do
      assert {:ok, {:tuesday, ~T[19:30:00]}} = TimeParser.parse_time_text("Tuesdays at 7:30pm")
    end

    test "parses 'Monday nights at 8pm'" do
      assert {:ok, {:monday, ~T[20:00:00]}} = TimeParser.parse_time_text("Monday nights at 8pm")
    end

    test "parses 'Friday at 9:00 PM'" do
      assert {:ok, {:friday, ~T[21:00:00]}} = TimeParser.parse_time_text("Friday at 9:00 PM")
    end

    test "returns error for nil time_text" do
      assert {:error, "Time text is nil"} = TimeParser.parse_time_text(nil)
    end

    test "returns error for text without day of week" do
      assert {:error, _} = TimeParser.parse_time_text("at 7pm")
    end

    test "returns error for text without time" do
      assert {:error, _} = TimeParser.parse_time_text("Wednesdays")
    end
  end

  describe "parse_day_of_week/1" do
    test "parses Monday variants" do
      assert {:ok, :monday} = TimeParser.parse_day_of_week("Monday")
      assert {:ok, :monday} = TimeParser.parse_day_of_week("Mondays")
      assert {:ok, :monday} = TimeParser.parse_day_of_week("Mon")
      assert {:ok, :monday} = TimeParser.parse_day_of_week("monday nights")
    end

    test "parses Tuesday variants" do
      assert {:ok, :tuesday} = TimeParser.parse_day_of_week("Tuesday")
      assert {:ok, :tuesday} = TimeParser.parse_day_of_week("Tuesdays")
      assert {:ok, :tuesday} = TimeParser.parse_day_of_week("Tues")
    end

    test "parses Wednesday variants" do
      assert {:ok, :wednesday} = TimeParser.parse_day_of_week("Wednesday")
      assert {:ok, :wednesday} = TimeParser.parse_day_of_week("Wednesdays")
      assert {:ok, :wednesday} = TimeParser.parse_day_of_week("Wed")
    end

    test "parses Thursday variants" do
      assert {:ok, :thursday} = TimeParser.parse_day_of_week("Thursday")
      assert {:ok, :thursday} = TimeParser.parse_day_of_week("Thursdays")
      assert {:ok, :thursday} = TimeParser.parse_day_of_week("Thurs")
    end

    test "parses Friday variants" do
      assert {:ok, :friday} = TimeParser.parse_day_of_week("Friday")
      assert {:ok, :friday} = TimeParser.parse_day_of_week("Fridays")
      assert {:ok, :friday} = TimeParser.parse_day_of_week("Fri")
    end

    test "parses Saturday variants" do
      assert {:ok, :saturday} = TimeParser.parse_day_of_week("Saturday")
      assert {:ok, :saturday} = TimeParser.parse_day_of_week("Saturdays")
      assert {:ok, :saturday} = TimeParser.parse_day_of_week("Sat")
    end

    test "parses Sunday variants" do
      assert {:ok, :sunday} = TimeParser.parse_day_of_week("Sunday")
      assert {:ok, :sunday} = TimeParser.parse_day_of_week("Sundays")
      assert {:ok, :sunday} = TimeParser.parse_day_of_week("Sun")
    end

    test "is case insensitive" do
      assert {:ok, :wednesday} = TimeParser.parse_day_of_week("WEDNESDAY")
      assert {:ok, :wednesday} = TimeParser.parse_day_of_week("wednesday")
      assert {:ok, :wednesday} = TimeParser.parse_day_of_week("WeDnEsDaY")
    end

    test "returns error for invalid day" do
      assert {:error, _} = TimeParser.parse_day_of_week("Notaday")
      assert {:error, _} = TimeParser.parse_day_of_week("123")
      assert {:error, _} = TimeParser.parse_day_of_week("")
    end
  end

  describe "parse_time/1" do
    test "parses 12-hour format with pm" do
      assert {:ok, ~T[19:00:00]} = TimeParser.parse_time("7pm")
      assert {:ok, ~T[20:00:00]} = TimeParser.parse_time("8pm")
      assert {:ok, ~T[21:00:00]} = TimeParser.parse_time("9pm")
    end

    test "parses 12-hour format with PM (uppercase)" do
      assert {:ok, ~T[19:00:00]} = TimeParser.parse_time("7 PM")
      assert {:ok, ~T[20:00:00]} = TimeParser.parse_time("8:00 PM")
    end

    test "parses 12-hour format with minutes" do
      assert {:ok, ~T[19:30:00]} = TimeParser.parse_time("7:30pm")
      assert {:ok, ~T[20:15:00]} = TimeParser.parse_time("8:15 PM")
      assert {:ok, ~T[21:45:00]} = TimeParser.parse_time("9:45pm")
    end

    test "parses 12-hour format with am" do
      assert {:ok, ~T[07:00:00]} = TimeParser.parse_time("7am")
      assert {:ok, ~T[08:30:00]} = TimeParser.parse_time("8:30 AM")
    end

    test "parses noon and midnight" do
      assert {:ok, ~T[12:00:00]} = TimeParser.parse_time("12pm")
      assert {:ok, ~T[00:00:00]} = TimeParser.parse_time("12am")
    end

    test "parses 24-hour format" do
      assert {:ok, ~T[19:00:00]} = TimeParser.parse_time("19:00")
      assert {:ok, ~T[20:30:00]} = TimeParser.parse_time("20:30")
      assert {:ok, ~T[13:45:00]} = TimeParser.parse_time("13:45")
    end

    test "parses time within context text" do
      assert {:ok, ~T[19:00:00]} = TimeParser.parse_time("at 7pm")
      assert {:ok, ~T[20:00:00]} = TimeParser.parse_time("starts at 8:00 PM")
      assert {:ok, ~T[19:30:00]} = TimeParser.parse_time("Trivia begins 7:30pm")
    end

    test "returns error for invalid time" do
      assert {:error, _} = TimeParser.parse_time("no time here")
      assert {:error, _} = TimeParser.parse_time("")
    end

    test "returns error for invalid hour" do
      assert {:error, _} = TimeParser.parse_time("25:00")
      assert {:error, _} = TimeParser.parse_time("13pm")
    end
  end

  describe "next_occurrence/3" do
    test "calculates next occurrence for a future day" do
      # This test is time-dependent, so we'll just verify it returns a DateTime
      result = TimeParser.next_occurrence(:wednesday, ~T[19:00:00])
      assert %DateTime{} = result
      assert result.time_zone == "Etc/UTC"
    end

    test "calculates next occurrence with custom timezone" do
      result = TimeParser.next_occurrence(:thursday, ~T[20:00:00], "America/Chicago")
      assert %DateTime{} = result
      assert result.time_zone == "Etc/UTC"
    end

    test "returns next week if day has already passed" do
      # Calculate for yesterday - should return next week
      yesterday = Date.day_of_week(Date.utc_today(), :monday) - 1
      yesterday_atom = day_number_to_atom(if yesterday == 0, do: 7, else: yesterday)

      result = TimeParser.next_occurrence(yesterday_atom, ~T[00:00:00])
      assert %DateTime{} = result

      # Should be in the future
      assert DateTime.compare(result, DateTime.utc_now()) == :gt
    end
  end

  # Helper to convert day number to atom for testing
  defp day_number_to_atom(1), do: :monday
  defp day_number_to_atom(2), do: :tuesday
  defp day_number_to_atom(3), do: :wednesday
  defp day_number_to_atom(4), do: :thursday
  defp day_number_to_atom(5), do: :friday
  defp day_number_to_atom(6), do: :saturday
  defp day_number_to_atom(7), do: :sunday
end
