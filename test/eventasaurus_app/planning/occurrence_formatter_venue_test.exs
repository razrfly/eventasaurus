defmodule EventasaurusApp.Planning.OccurrenceFormatterVenueTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Planning.OccurrenceFormatter

  describe "format_venue_options/2" do
    test "formats venue time slots into poll option attributes" do
      occurrences = [
        %{
          venue_id: 123,
          venue_name: "La Forchetta",
          venue_city_id: 1,
          date: ~D[2024-11-25],
          meal_period: "dinner",
          starts_at: ~U[2024-11-25 18:00:00Z],
          ends_at: ~U[2024-11-25 22:00:00Z]
        },
        %{
          venue_id: 123,
          venue_name: "La Forchetta",
          venue_city_id: 1,
          date: ~D[2024-11-26],
          meal_period: "lunch",
          starts_at: ~U[2024-11-26 12:00:00Z],
          ends_at: ~U[2024-11-26 15:00:00Z]
        }
      ]

      options = OccurrenceFormatter.format_venue_options(occurrences)

      assert length(options) == 2

      [dinner_option, lunch_option] = options

      # Check dinner option
      assert dinner_option.title == "La Forchetta - Dinner"
      assert dinner_option.description =~ "Monday"
      assert dinner_option.description =~ "Nov 25"
      assert dinner_option.description =~ "6:00 PM to 10:00 PM"
      assert dinner_option.external_id == "venue_slot:123:2024-11-25:dinner"
      assert dinner_option.metadata.occurrence_type == "venue_time_slot"
      assert dinner_option.metadata.venue_id == 123
      assert dinner_option.metadata.meal_period == "dinner"
      assert dinner_option.order_index == 0

      # Check lunch option
      assert lunch_option.title == "La Forchetta - Lunch"
      assert lunch_option.description =~ "Tuesday"
      assert lunch_option.description =~ "Nov 26"
      assert lunch_option.description =~ "12:00 PM to 03:00 PM"
      assert lunch_option.external_id == "venue_slot:123:2024-11-26:lunch"
      assert lunch_option.order_index == 1
    end

    test "capitalizes meal period in title" do
      occurrence = %{
        venue_id: 123,
        venue_name: "Test Venue",
        venue_city_id: 1,
        date: ~D[2024-11-25],
        meal_period: "breakfast",
        starts_at: ~U[2024-11-25 08:00:00Z],
        ends_at: ~U[2024-11-25 11:00:00Z]
      }

      [option] = OccurrenceFormatter.format_venue_options([occurrence])

      assert option.title == "Test Venue - Breakfast"
    end

    test "formats brunch correctly" do
      occurrence = %{
        venue_id: 123,
        venue_name: "Weekend Spot",
        venue_city_id: 1,
        date: ~D[2024-11-30],
        # Saturday
        meal_period: "brunch",
        starts_at: ~U[2024-11-30 10:00:00Z],
        ends_at: ~U[2024-11-30 14:00:00Z]
      }

      [option] = OccurrenceFormatter.format_venue_options([occurrence])

      assert option.title == "Weekend Spot - Brunch"
      assert option.description =~ "Saturday"
      assert option.description =~ "10:00 AM to 02:00 PM"
    end

    test "external_data includes all venue occurrence fields" do
      occurrence = %{
        venue_id: 789,
        venue_name: "Test Restaurant",
        venue_city_id: 2,
        date: ~D[2024-11-25],
        meal_period: "dinner",
        starts_at: ~U[2024-11-25 18:00:00Z],
        ends_at: ~U[2024-11-25 22:00:00Z]
      }

      [option] = OccurrenceFormatter.format_venue_options([occurrence])

      external_data = option.external_data

      assert external_data["venue_id"] == 789
      assert external_data["venue_name"] == "Test Restaurant"
      assert external_data["date"] == "2024-11-25"
      assert external_data["meal_period"] == "dinner"
      assert external_data["starts_at"] == "2024-11-25T18:00:00Z"
      assert external_data["ends_at"] == "2024-11-25T22:00:00Z"
    end

    test "metadata includes occurrence type and venue details" do
      occurrence = %{
        venue_id: 456,
        venue_name: "Bistro",
        venue_city_id: 1,
        date: ~D[2024-11-25],
        meal_period: "lunch",
        starts_at: ~U[2024-11-25 12:00:00Z],
        ends_at: ~U[2024-11-25 15:00:00Z]
      }

      [option] = OccurrenceFormatter.format_venue_options([occurrence])

      metadata = option.metadata

      assert metadata.occurrence_type == "venue_time_slot"
      assert metadata.venue_id == 456
      assert metadata.date == "2024-11-25"
      assert metadata.meal_period == "lunch"
      assert metadata.starts_at == "2024-11-25T12:00:00Z"
      assert metadata.ends_at == "2024-11-25T15:00:00Z"
    end

    test "handles different time zones" do
      occurrence = %{
        venue_id: 123,
        venue_name: "Test Venue",
        venue_city_id: 1,
        date: ~D[2024-11-25],
        meal_period: "dinner",
        starts_at: ~U[2024-11-25 23:00:00Z],
        # 11 PM UTC
        ends_at: ~U[2024-11-26 03:00:00Z]
        # 3 AM UTC next day
      }

      [option] = OccurrenceFormatter.format_venue_options([occurrence], timezone: "America/New_York")

      # 11 PM UTC = 6 PM EST (UTC-5)
      assert option.description =~ "6:00 PM to 10:00 PM"
    end
  end

  describe "format_options/2 with venue occurrences" do
    test "automatically detects and formats venue occurrences" do
      venue_occurrences = [
        %{
          venue_id: 123,
          venue_name: "Restaurant",
          venue_city_id: 1,
          date: ~D[2024-11-25],
          meal_period: "dinner",
          starts_at: ~U[2024-11-25 18:00:00Z],
          ends_at: ~U[2024-11-25 22:00:00Z]
        }
      ]

      [option] = OccurrenceFormatter.format_options(venue_occurrences)

      # Should use venue formatting
      assert option.title == "Restaurant - Dinner"
      assert option.external_id =~ "venue_slot:"
      assert option.metadata.occurrence_type == "venue_time_slot"
    end

    test "distinguishes venue occurrences from movie occurrences" do
      movie_occurrences = [
        %{
          public_event_id: 456,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 789,
          venue_name: "Cinema",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: ~U[2024-11-25 21:00:00Z]
        }
      ]

      [movie_option] = OccurrenceFormatter.format_options(movie_occurrences)

      # Should use movie formatting
      assert movie_option.title =~ "Test Movie @ Cinema"
      assert movie_option.external_id =~ "event:"

      venue_occurrences = [
        %{
          venue_id: 123,
          venue_name: "Restaurant",
          venue_city_id: 1,
          date: ~D[2024-11-25],
          meal_period: "dinner",
          starts_at: ~U[2024-11-25 18:00:00Z],
          ends_at: ~U[2024-11-25 22:00:00Z]
        }
      ]

      [venue_option] = OccurrenceFormatter.format_options(venue_occurrences)

      # Should use venue formatting
      assert venue_option.title =~ "Restaurant - Dinner"
      assert venue_option.external_id =~ "venue_slot:"
    end
  end
end
