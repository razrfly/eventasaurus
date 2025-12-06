defmodule EventasaurusDiscovery.Scraping.Processors.EventProcessorConcurrencyTest do
  # Note: We use async: false and shared sandbox mode because these tests
  # use Task.async_stream which spawns new processes that need DB access
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "concurrent event processing with advisory locks" do
    setup do
      # Set sandbox to shared mode so spawned tasks can access the DB
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      # Use Poland (a real country the system knows about) to avoid validation issues
      {:ok, country} =
        Repo.insert(%Country{
          name: "Poland",
          code: "PL",
          slug: "poland-#{System.unique_integer([:positive])}"
        })

      # Use Krakow as a real city name that the system can recognize
      {:ok, city} =
        Repo.insert(%City{
          name: "Krakow",
          slug: "krakow-#{System.unique_integer([:positive])}",
          country_id: country.id,
          latitude: 50.0617,
          longitude: 19.9372
        })

      # Create test venue in Krakow
      {:ok, venue} =
        Repo.insert(%Venue{
          name: "Test Venue Krakow",
          slug: "test-venue-krakow-#{System.unique_integer([:positive])}",
          city_id: city.id,
          address: "Rynek Główny 1",
          latitude: 50.0617,
          longitude: 19.9372
        })

      # Create test source
      {:ok, source} =
        Repo.insert(%Source{
          name: "Test Source",
          slug: "test-source-#{System.unique_integer([:positive])}",
          website_url: "https://test.com",
          priority: 10,
          is_active: true
        })

      %{venue: venue, source: source, city: city, country: country}
    end

    test "event and venue are linked atomically", %{
      venue: venue,
      source: source,
      city: city,
      country: country
    } do
      # Test that event and venue are properly linked in a single atomic operation
      base_time = DateTime.utc_now() |> DateTime.add(30, :day)
      unique_suffix = System.unique_integer([:positive])

      event_data = %{
        external_id: "atomic_test_#{unique_suffix}",
        title: "Atomic Transaction Test Event",
        start_at: base_time,
        venue_data: %{
          name: venue.name,
          address: venue.address,
          city: city.name,
          country: country.name,
          latitude: venue.latitude,
          longitude: venue.longitude
        },
        source_url: "https://test.com/atomic/#{unique_suffix}",
        image_url: "https://test.com/image.jpg"
      }

      # Process single event - uses existing venue
      result = EventProcessor.process_event(event_data, source.id, source.priority)

      # Should succeed
      assert {:ok, event} = result
      assert event.id != nil
      assert event.venue_id != nil

      # Verify both event and venue exist in DB
      db_event = Repo.get(PublicEvent, event.id)
      assert db_event != nil, "Event should exist in database"

      db_venue = Repo.get(EventasaurusApp.Venues.Venue, event.venue_id)
      assert db_venue != nil, "Venue should exist in database"

      # Verify the event is linked to the venue
      assert db_event.venue_id == db_venue.id, "Event should be linked to venue"
    end

    test "processes multiple events in parallel without errors", %{venue: venue, source: source, city: city, country: country} do
      # Create 3 different events at the same venue
      base_time = DateTime.utc_now() |> DateTime.add(30, :day)
      unique_suffix = System.unique_integer([:positive])

      event_data_list = [
        %{
          external_id: "parallel_event_a_#{unique_suffix}",
          title: "Parallel Event A",
          start_at: base_time,
          venue_data: %{
            name: venue.name,
            address: venue.address,
            city: city.name,
            country: country.name,
            latitude: 50.0617,
            longitude: 19.9372
          },
          source_url: "https://test.com/parallel/a/#{unique_suffix}"
        },
        %{
          external_id: "parallel_event_b_#{unique_suffix}",
          title: "Parallel Event B",
          start_at: DateTime.add(base_time, 1, :day),
          venue_data: %{
            name: venue.name,
            address: venue.address,
            city: city.name,
            country: country.name,
            latitude: 50.0617,
            longitude: 19.9372
          },
          source_url: "https://test.com/parallel/b/#{unique_suffix}"
        },
        %{
          external_id: "parallel_event_c_#{unique_suffix}",
          title: "Parallel Event C",
          start_at: DateTime.add(base_time, 2, :day),
          venue_data: %{
            name: venue.name,
            address: venue.address,
            city: city.name,
            country: country.name,
            latitude: 50.0617,
            longitude: 19.9372
          },
          source_url: "https://test.com/parallel/c/#{unique_suffix}"
        }
      ]

      # Process all events concurrently
      results =
        Task.async_stream(
          event_data_list,
          fn event_data ->
            EventProcessor.process_event(event_data, source.id, source.priority)
          end,
          max_concurrency: 3,
          timeout: 30_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      # All should succeed (no errors during parallel processing)
      success_count = Enum.count(results, fn result -> match?({:ok, _}, result) end)
      assert success_count == 3, "Expected all 3 events to process successfully, got #{success_count}"

      # All successful events should have valid IDs
      successful_events = Enum.filter(results, fn result -> match?({:ok, _}, result) end)
      assert Enum.all?(successful_events, fn {:ok, event} -> event.id != nil end)
    end

    test "sequential processing of multiple events works correctly", %{
      venue: venue,
      source: source,
      city: city,
      country: country
    } do
      # Test that multiple events can be processed sequentially without issues
      # This verifies the Ecto.Multi atomic behavior works for repeated calls
      base_time = DateTime.utc_now() |> DateTime.add(30, :day)
      unique_suffix = System.unique_integer([:positive])

      # Process 3 events sequentially (not concurrently)
      results =
        Enum.map(1..3, fn i ->
          event_data = %{
            external_id: "sequential_test_#{unique_suffix}_#{i}",
            title: "Sequential Test Event #{i}",
            start_at: DateTime.add(base_time, i - 1, :day),
            venue_data: %{
              name: venue.name,
              address: venue.address,
              city: city.name,
              country: country.name,
              latitude: venue.latitude,
              longitude: venue.longitude
            },
            source_url: "https://test.com/sequential/#{unique_suffix}/#{i}"
          }

          EventProcessor.process_event(event_data, source.id, source.priority)
        end)

      # All should succeed
      success_count = Enum.count(results, fn result -> match?({:ok, _}, result) end)

      assert success_count == 3,
             "Expected all 3 events to succeed, got #{success_count}"

      # All events should have valid IDs and venue_ids
      successful_events = Enum.filter(results, fn result -> match?({:ok, _}, result) end)

      assert Enum.all?(successful_events, fn {:ok, event} ->
               event.id != nil and event.venue_id != nil
             end),
             "All events should have both event.id and venue_id set atomically"
    end
  end
end
