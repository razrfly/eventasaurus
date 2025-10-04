defmodule EventasaurusDiscovery.Scraping.Processors.EventProcessorConcurrencyTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Sources.Source

  describe "concurrent event processing with advisory locks" do
    setup do
      # Create test venue
      {:ok, venue} =
        Repo.insert(%Venue{
          name: "Test Venue",
          slug: "test-venue-#{System.unique_integer([:positive])}",
          city_id: 1,
          address: "123 Test St",
          latitude: Decimal.new("50.0"),
          longitude: Decimal.new("19.9")
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

      %{venue: venue, source: source}
    end

    test "prevents duplicate events when processing same event concurrently", %{
      venue: venue,
      source: source
    } do
      # Create 5 identical events (same title, venue, different external_ids)
      base_time = DateTime.utc_now() |> DateTime.add(30, :day)

      event_data_list =
        Enum.map(1..5, fn i ->
          %{
            external_id: "test_event_#{i}",
            title: "Recurring Test Event",
            start_at: DateTime.add(base_time, i - 1, :day),
            venue_data: %{
              name: venue.name,
              address: venue.address,
              city_name: "Krakow",
              latitude: 50.0,
              longitude: 19.9
            },
            source_url: "https://test.com/event/#{i}",
            image_url: "https://test.com/image.jpg"
          }
        end)

      # Process all events concurrently using Task.async_stream
      results =
        Task.async_stream(
          event_data_list,
          fn event_data ->
            EventProcessor.process_event(event_data, source.id, source.priority)
          end,
          max_concurrency: 5,
          timeout: 30_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      # All should succeed
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)

      # Extract all event IDs from results
      event_ids =
        Enum.map(results, fn {:ok, event} -> event.id end)
        |> Enum.uniq()

      # Should have created ONLY 1 event (all consolidated)
      assert length(event_ids) == 1,
             "Expected 1 event, got #{length(event_ids)} events: #{inspect(event_ids)}"

      # Verify the single event has 5 occurrences
      [event_id] = event_ids
      event = Repo.get!(PublicEvent, event_id)

      occurrence_count = length(get_in(event.occurrences, ["dates"]) || [])
      assert occurrence_count == 5, "Expected 5 occurrences, got #{occurrence_count}"
    end

    test "allows parallel processing of different events", %{venue: venue, source: source} do
      # Create 3 completely different events
      base_time = DateTime.utc_now() |> DateTime.add(30, :day)

      event_data_list = [
        %{
          external_id: "different_event_1",
          title: "Event A",
          start_at: base_time,
          venue_data: %{
            name: venue.name,
            address: venue.address,
            city_name: "Krakow",
            latitude: 50.0,
            longitude: 19.9
          },
          source_url: "https://test.com/event/a"
        },
        %{
          external_id: "different_event_2",
          title: "Event B",
          start_at: base_time,
          venue_data: %{
            name: venue.name,
            address: venue.address,
            city_name: "Krakow",
            latitude: 50.0,
            longitude: 19.9
          },
          source_url: "https://test.com/event/b"
        },
        %{
          external_id: "different_event_3",
          title: "Event C",
          start_at: base_time,
          venue_data: %{
            name: venue.name,
            address: venue.address,
            city_name: "Krakow",
            latitude: 50.0,
            longitude: 19.9
          },
          source_url: "https://test.com/event/c"
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

      # All should succeed
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)

      # Extract all event IDs
      event_ids =
        Enum.map(results, fn {:ok, event} -> event.id end)
        |> Enum.uniq()

      # Should have created 3 separate events (not consolidated)
      assert length(event_ids) == 3, "Expected 3 different events, got #{length(event_ids)}"
    end

    test "stress test: 10 concurrent identical events", %{venue: venue, source: source} do
      base_time = DateTime.utc_now() |> DateTime.add(30, :day)

      # Create 10 identical recurring events
      event_data_list =
        Enum.map(1..10, fn i ->
          %{
            external_id: "stress_test_#{i}",
            title: "Stress Test Recurring Event",
            start_at: DateTime.add(base_time, i - 1, :day),
            venue_data: %{
              name: venue.name,
              address: venue.address,
              city_name: "Krakow",
              latitude: 50.0,
              longitude: 19.9
            },
            source_url: "https://test.com/stress/#{i}"
          }
        end)

      # Process with high concurrency
      results =
        Task.async_stream(
          event_data_list,
          fn event_data ->
            EventProcessor.process_event(event_data, source.id, source.priority)
          end,
          max_concurrency: 10,
          timeout: 60_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      # All should succeed
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)

      # Extract unique event IDs
      event_ids =
        Enum.map(results, fn {:ok, event} -> event.id end)
        |> Enum.uniq()

      # Should have created ONLY 1 event
      assert length(event_ids) == 1, "Expected 1 event under stress, got #{length(event_ids)}"

      # Verify 10 occurrences
      [event_id] = event_ids
      event = Repo.get!(PublicEvent, event_id)

      occurrence_count = length(get_in(event.occurrences, ["dates"]) || [])
      assert occurrence_count == 10, "Expected 10 occurrences, got #{occurrence_count}"
    end
  end
end
