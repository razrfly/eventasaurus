defmodule EventasaurusDiscovery.Sources.PubquizPl.TransformerTest do
  @moduledoc """
  Tests for PubQuiz transformer.

  Ensures stable recurrence rule generation and proper event transformation.
  """

  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.PubquizPl.Transformer

  describe "build_title/1" do
    test "cleans up venue name and creates standardized title" do
      assert Transformer.build_title("PubQuiz.pl - Test Venue") ==
               "Weekly Trivia Night - Test Venue"

      assert Transformer.build_title("Pub Quiz - Another Venue") ==
               "Weekly Trivia Night - Another Venue"

      assert Transformer.build_title("Simple Venue Name") ==
               "Weekly Trivia Night - Simple Venue Name"
    end
  end

  describe "parse_schedule_to_recurrence/1" do
    test "parses Polish Monday schedule" do
      {:ok, rule} = Transformer.parse_schedule_to_recurrence("Każdy poniedziałek 19:00")

      assert rule["frequency"] == "weekly"
      assert rule["days_of_week"] == ["monday"]
      assert rule["time"] == "19:00"
      assert rule["timezone"] == "Europe/Warsaw"
    end

    test "parses Polish Tuesday schedule with plural form" do
      {:ok, rule} = Transformer.parse_schedule_to_recurrence("Wtorki o 20:00")

      assert rule["frequency"] == "weekly"
      assert rule["days_of_week"] == ["tuesday"]
      assert rule["time"] == "20:00"
      assert rule["timezone"] == "Europe/Warsaw"
    end

    test "parses schedule with single-digit hour" do
      {:ok, rule} = Transformer.parse_schedule_to_recurrence("Środa 9:30")

      assert rule["time"] == "09:30"
    end

    test "handles various Polish day names" do
      test_cases = [
        {"poniedziałek", "monday"},
        {"wtorek", "tuesday"},
        {"środa", "wednesday"},
        {"czwartek", "thursday"},
        {"piątek", "friday"},
        {"sobota", "saturday"},
        {"niedziela", "sunday"}
      ]

      for {polish_day, expected_day} <- test_cases do
        {:ok, rule} = Transformer.parse_schedule_to_recurrence("#{polish_day} 18:00")
        assert rule["days_of_week"] == [expected_day]
      end
    end

    test "rejects invalid schedule text" do
      assert {:error, :no_day_found} =
               Transformer.parse_schedule_to_recurrence("Invalid schedule")

      assert {:error, :no_schedule} = Transformer.parse_schedule_to_recurrence(nil)
      assert {:error, :no_schedule} = Transformer.parse_schedule_to_recurrence("")
    end
  end

  describe "calculate_next_occurrence/1" do
    test "calculates next occurrence for future day this week" do
      # Monday at 19:00
      rule = %{
        "frequency" => "weekly",
        "days_of_week" => ["monday"],
        "time" => "19:00",
        "timezone" => "Europe/Warsaw"
      }

      {:ok, next_occurrence} = Transformer.calculate_next_occurrence(rule)

      # Verify it's a DateTime
      assert %DateTime{} = next_occurrence

      # Verify day of week is Monday
      assert Date.day_of_week(DateTime.to_date(next_occurrence)) == 1

      # Verify time
      assert next_occurrence.hour == 19
      assert next_occurrence.minute == 0
    end

    test "calculates next occurrence for multiple days" do
      days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

      for {day, day_num} <- Enum.with_index(days, 1) do
        rule = %{
          "frequency" => "weekly",
          "days_of_week" => [day],
          "time" => "20:00",
          "timezone" => "Europe/Warsaw"
        }

        {:ok, next_occurrence} = Transformer.calculate_next_occurrence(rule)

        # Verify correct day of week
        assert Date.day_of_week(DateTime.to_date(next_occurrence)) == day_num

        # Verify correct time
        assert next_occurrence.hour == 20
        assert next_occurrence.minute == 0
      end
    end
  end

  describe "transform_venue_to_event/3" do
    test "transforms venue data to event with recurrence" do
      venue_data = %{
        name: "PubQuiz.pl - Test Venue",
        schedule: "Każdy poniedziałek 19:00",
        host: "Test Host",
        phone: "123-456-789",
        description: "Weekly quiz night"
      }

      venue_record = %{
        id: 1,
        latitude: 50.0614,
        longitude: 19.9372
      }

      city_record = %{id: 1, name: "Kraków"}

      {:ok, event} = Transformer.transform_venue_to_event(venue_data, venue_record, city_record)

      # Verify required fields
      assert event.title == "Weekly Trivia Night - Test Venue"
      assert event.venue_id == 1
      assert %DateTime{} = event.starts_at
      assert %DateTime{} = event.ends_at

      # Verify recurrence rule
      assert event.recurrence_rule["frequency"] == "weekly"
      assert event.recurrence_rule["days_of_week"] == ["monday"]
      assert event.recurrence_rule["time"] == "19:00"

      # Verify source metadata
      assert event.source_metadata["venue_name"] == "PubQuiz.pl - Test Venue"
      assert event.source_metadata["host"] == "Test Host"
      assert event.source_metadata["schedule_text"] == "Każdy poniedziałek 19:00"
    end

    test "calculates 2-hour duration" do
      venue_data = %{
        name: "Test Venue",
        schedule: "wtorek 20:00"
      }

      venue_record = %{id: 1}
      city_record = %{id: 1}

      {:ok, event} = Transformer.transform_venue_to_event(venue_data, venue_record, city_record)

      # Verify 2-hour duration
      duration_seconds = DateTime.diff(event.ends_at, event.starts_at)
      assert duration_seconds == 2 * 3600
    end

    test "rejects venue without valid schedule" do
      venue_data = %{
        name: "Test Venue",
        schedule: "Invalid schedule"
      }

      venue_record = %{id: 1}
      city_record = %{id: 1}

      result = Transformer.transform_venue_to_event(venue_data, venue_record, city_record)

      # Should error on invalid schedule
      assert {:error, _reason} = result
    end
  end
end
