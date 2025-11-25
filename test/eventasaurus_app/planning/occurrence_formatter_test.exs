defmodule EventasaurusApp.Planning.OccurrenceFormatterTest do
  use ExUnit.Case, async: true

  alias EventasaurusApp.Planning.OccurrenceFormatter

  describe "format_movie_options/2" do
    test "formats movie occurrences into poll options" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Dune: Part Two",
          venue_id: 456,
          venue_name: "Cinema City Arkadia",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: ~U[2024-11-25 21:30:00Z]
        }
      ]

      [option] = OccurrenceFormatter.format_movie_options(occurrences)

      assert option.title == "Dune: Part Two @ Cinema City Arkadia"
      assert option.description == "Monday, Nov 25 at 07:00 PM"
      assert option.external_id == "event:1"
      assert option.order_index == 0
    end

    test "sets order_index chronologically" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Movie A",
          venue_id: 456,
          venue_name: "Venue A",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: ~U[2024-11-25 21:00:00Z]
        },
        %{
          public_event_id: 2,
          movie_id: 123,
          movie_title: "Movie A",
          venue_id: 456,
          venue_name: "Venue A",
          starts_at: ~U[2024-11-25 21:00:00Z],
          ends_at: ~U[2024-11-25 23:00:00Z]
        }
      ]

      [option1, option2] = OccurrenceFormatter.format_movie_options(occurrences)

      assert option1.order_index == 0
      assert option2.order_index == 1
    end

    test "includes occurrence metadata" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 456,
          venue_name: "Test Venue",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: ~U[2024-11-25 21:00:00Z]
        }
      ]

      [option] = OccurrenceFormatter.format_movie_options(occurrences)

      assert option.metadata.occurrence_type == "movie_showtime"
      assert option.metadata.public_event_id == 1
      assert option.metadata.movie_id == 123
      assert option.metadata.venue_id == 456
      assert option.metadata.starts_at == "2024-11-25T19:00:00Z"
    end

    test "respects timezone option" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 456,
          venue_name: "Test Venue",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: nil
        }
      ]

      [option] =
        OccurrenceFormatter.format_movie_options(occurrences, timezone: "America/New_York")

      # 19:00 UTC = 14:00 EST (or 15:00 EDT depending on DST)
      assert String.contains?(option.description, "02:00 PM") or
               String.contains?(option.description, "03:00 PM")
    end
  end

  describe "format_discovery_options/2" do
    test "formats discovery occurrences with movie titles" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Movie A",
          venue_id: 456,
          venue_name: "Venue A",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: nil
        },
        %{
          public_event_id: 2,
          movie_id: 456,
          movie_title: "Movie B",
          venue_id: 789,
          venue_name: "Venue B",
          starts_at: ~U[2024-11-25 20:00:00Z],
          ends_at: nil
        }
      ]

      options = OccurrenceFormatter.format_discovery_options(occurrences)

      assert length(options) == 2
      assert Enum.at(options, 0).title == "Movie A @ Venue A"
      assert Enum.at(options, 1).title == "Movie B @ Venue B"
    end
  end

  describe "format_options/2" do
    test "delegates to format_movie_options for single movie" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 456,
          venue_name: "Test Venue",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: nil
        },
        %{
          public_event_id: 2,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 789,
          venue_name: "Other Venue",
          starts_at: ~U[2024-11-25 20:00:00Z],
          ends_at: nil
        }
      ]

      options = OccurrenceFormatter.format_options(occurrences)

      assert length(options) == 2
      assert Enum.all?(options, fn opt -> String.contains?(opt.title, "Test Movie") end)
    end

    test "delegates to format_discovery_options for multiple movies" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Movie A",
          venue_id: 456,
          venue_name: "Venue A",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: nil
        },
        %{
          public_event_id: 2,
          movie_id: 456,
          movie_title: "Movie B",
          venue_id: 789,
          venue_name: "Venue B",
          starts_at: ~U[2024-11-25 20:00:00Z],
          ends_at: nil
        }
      ]

      options = OccurrenceFormatter.format_options(occurrences)

      assert length(options) == 2
      assert Enum.at(options, 0).title == "Movie A @ Venue A"
      assert Enum.at(options, 1).title == "Movie B @ Venue B"
    end
  end

  describe "format_grouped_by_date/2" do
    test "groups occurrences by date" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 456,
          venue_name: "Test Venue",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: nil
        },
        %{
          public_event_id: 2,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 456,
          venue_name: "Test Venue",
          starts_at: ~U[2024-11-25 21:00:00Z],
          ends_at: nil
        },
        %{
          public_event_id: 3,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 456,
          venue_name: "Test Venue",
          starts_at: ~U[2024-11-26 19:00:00Z],
          ends_at: nil
        }
      ]

      groups = OccurrenceFormatter.format_grouped_by_date(occurrences)

      assert length(groups) == 2
      assert Enum.at(groups, 0).date == ~D[2024-11-25]
      assert length(Enum.at(groups, 0).options) == 2
      assert Enum.at(groups, 1).date == ~D[2024-11-26]
      assert length(Enum.at(groups, 1).options) == 1
    end

    test "includes formatted date labels" do
      occurrences = [
        %{
          public_event_id: 1,
          movie_id: 123,
          movie_title: "Test Movie",
          venue_id: 456,
          venue_name: "Test Venue",
          starts_at: ~U[2024-11-25 19:00:00Z],
          ends_at: nil
        }
      ]

      [group] = OccurrenceFormatter.format_grouped_by_date(occurrences)

      assert group.date_label == "Monday, November 25"
    end
  end
end
