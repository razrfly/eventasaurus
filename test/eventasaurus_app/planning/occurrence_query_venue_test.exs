defmodule EventasaurusApp.Planning.OccurrenceQueryVenueTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Planning.OccurrenceQuery
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusApp.Repo

  setup do
    # Create test country
    {:ok, country} =
      Country.changeset(%Country{}, %{name: "United States", code: "US"})
      |> Repo.insert()

    # Create test city
    {:ok, city} =
      City.changeset(%City{}, %{
        name: "Test City",
        country_id: country.id,
        latitude: Decimal.new("40.7128"),
        longitude: Decimal.new("-74.0060")
      })
      |> Repo.insert()

    # Create test venue
    {:ok, venue} =
      Venue.changeset(%Venue{}, %{
        name: "Test Restaurant",
        venue_type: "venue",
        source: "user",
        latitude: 40.7128,
        longitude: -74.0060,
        city_id: city.id
      })
      |> Repo.insert()

    %{venue: venue, city: city}
  end

  describe "find_venue_occurrences/2" do
    test "generates time slots for a venue within date range", %{venue: venue} do
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-11-27]
        },
        meal_periods: ["dinner", "lunch"]
      }

      {:ok, occurrences} = OccurrenceQuery.find_venue_occurrences(venue.id, filter_criteria)

      # Should generate 3 days × 2 meal periods = 6 time slots
      assert length(occurrences) == 6
    end

    test "respects meal period filters", %{venue: venue} do
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-11-26]
        },
        meal_periods: ["dinner"]
      }

      {:ok, occurrences} = OccurrenceQuery.find_venue_occurrences(venue.id, filter_criteria)

      # Should only generate dinner slots
      assert length(occurrences) == 2
      assert Enum.all?(occurrences, fn occ -> occ.meal_period == "dinner" end)
    end

    test "defaults to breakfast, lunch, dinner when no meal periods specified", %{venue: venue} do
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-11-25]
        }
      }

      {:ok, occurrences} = OccurrenceQuery.find_venue_occurrences(venue.id, filter_criteria)

      # Should generate 3 default meal periods
      assert length(occurrences) == 3

      meal_periods = Enum.map(occurrences, & &1.meal_period)
      assert "breakfast" in meal_periods
      assert "lunch" in meal_periods
      assert "dinner" in meal_periods
    end

    test "only generates brunch on weekends", %{venue: venue} do
      # Nov 25, 2024 is Monday
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-11-25]
        },
        meal_periods: ["brunch"]
      }

      {:ok, occurrences} = OccurrenceQuery.find_venue_occurrences(venue.id, filter_criteria)

      # No brunch on Monday
      assert length(occurrences) == 0

      # Saturday (Nov 30, 2024) should have brunch
      saturday_filter = %{
        date_range: %{
          start: ~D[2024-11-30],
          end: ~D[2024-11-30]
        },
        meal_periods: ["brunch"]
      }

      {:ok, weekend_occurrences} =
        OccurrenceQuery.find_venue_occurrences(venue.id, saturday_filter)

      assert length(weekend_occurrences) == 1
    end

    test "generates correct time windows for each meal period", %{venue: venue} do
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-11-25]
        },
        meal_periods: ["breakfast", "lunch", "dinner"]
      }

      {:ok, occurrences} = OccurrenceQuery.find_venue_occurrences(venue.id, filter_criteria)

      breakfast = Enum.find(occurrences, &(&1.meal_period == "breakfast"))
      assert breakfast.starts_at.hour == 8
      assert breakfast.ends_at.hour == 11

      lunch = Enum.find(occurrences, &(&1.meal_period == "lunch"))
      assert lunch.starts_at.hour == 12
      assert lunch.ends_at.hour == 15

      dinner = Enum.find(occurrences, &(&1.meal_period == "dinner"))
      assert dinner.starts_at.hour == 18
      assert dinner.ends_at.hour == 22
    end

    test "respects limit parameter", %{venue: venue} do
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-12-25]
        },
        meal_periods: ["breakfast", "lunch", "dinner"],
        limit: 10
      }

      {:ok, occurrences} = OccurrenceQuery.find_venue_occurrences(venue.id, filter_criteria)

      assert length(occurrences) == 10
    end

    test "returns error when venue not found" do
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-11-27]
        }
      }

      assert {:error, reason} = OccurrenceQuery.find_venue_occurrences(999_999, filter_criteria)
      assert reason =~ "Venue not found"
    end

    test "occurrence structure includes all required fields", %{venue: venue} do
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-11-25]
        },
        meal_periods: ["dinner"]
      }

      {:ok, [occurrence]} = OccurrenceQuery.find_venue_occurrences(venue.id, filter_criteria)

      assert occurrence.venue_id == venue.id
      assert occurrence.venue_name == "Test Restaurant"
      assert occurrence.date == ~D[2024-11-25]
      assert occurrence.meal_period == "dinner"
      assert %DateTime{} = occurrence.starts_at
      assert %DateTime{} = occurrence.ends_at
    end
  end

  describe "find_occurrences/3 with venue type" do
    test "delegates to find_venue_occurrences for venue type", %{venue: venue} do
      filter_criteria = %{
        date_range: %{
          start: ~D[2024-11-25],
          end: ~D[2024-11-26]
        },
        meal_periods: ["dinner"]
      }

      {:ok, occurrences} = OccurrenceQuery.find_occurrences("venue", venue.id, filter_criteria)

      assert length(occurrences) == 2
      assert Enum.all?(occurrences, fn occ -> occ.meal_period == "dinner" end)
    end
  end
end
