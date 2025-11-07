defmodule EventasaurusDiscovery.Sources.ProcessorTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Sources.Processor
  alias EventasaurusDiscovery.ScraperProcessingLogs

  describe "process_single_event/3 with logging" do
    setup do
      source = create_test_source()
      {:ok, source: source}
    end

    test "logs success when event is processed successfully", %{source: source} do
      event_data = %{
        title: "Test Event",
        external_id: "test_123",
        starts_at: DateTime.utc_now() |> DateTime.add(86400, :second),
        ends_at: DateTime.utc_now() |> DateTime.add(90000, :second),
        description: "Test event description",
        venue_data: %{
          name: "Test Venue",
          address: "123 Test St",
          city: "Warsaw",
          country: "Poland",
          latitude: 52.2297,
          longitude: 21.0122
        }
      }

      # Count logs before processing
      initial_count = count_logs(source)

      # Process the event
      {:ok, _event} = Processor.process_single_event(event_data, source, "test_scraper")

      # Verify a success log was created
      assert count_logs(source) == initial_count + 1

      # Verify the log details
      stats = ScraperProcessingLogs.get_success_rate(source.name, 7)
      assert stats.success_count >= 1
      assert stats.failure_count == 0
    end

    test "logs failure when event processing fails", %{source: source} do
      # Event data with missing required fields (no venue)
      event_data = %{
        title: "Incomplete Event",
        external_id: "fail_123"
      }

      # Count logs before processing
      initial_count = count_logs(source)

      # Process the event (should fail)
      {:error, _reason} = Processor.process_single_event(event_data, source, "test_scraper")

      # Verify a failure log was created
      assert count_logs(source) == initial_count + 1

      # Verify the log details
      stats = ScraperProcessingLogs.get_success_rate(source.name, 7)
      assert stats.failure_count >= 1

      # Check that the error was categorized
      breakdown = ScraperProcessingLogs.get_error_breakdown(source.name, 7)
      assert length(breakdown) > 0
    end

    test "logs include metadata about the event", %{source: source} do
      event_data = %{
        title: "Metadata Test Event",
        external_id: "meta_456",
        starts_at: DateTime.utc_now() |> DateTime.add(86400, :second),
        ends_at: DateTime.utc_now() |> DateTime.add(90000, :second),
        venue_data: %{
          name: "Metadata Test Venue",
          address: "456 Meta St",
          city: "Krakow",
          country: "Poland",
          latitude: 50.0647,
          longitude: 19.9450
        }
      }

      # Process the event
      {:ok, _event} = Processor.process_single_event(event_data, source, "test_scraper")

      # Query for recent logs to verify metadata
      logs =
        from(l in EventasaurusDiscovery.ScraperProcessingLogs.ScraperProcessingLog,
          where: l.source_id == ^source.id,
          where: l.status == "success",
          order_by: [desc: l.processed_at],
          limit: 1
        )
        |> Repo.all()

      assert length(logs) == 1
      [log] = logs

      # Verify metadata was captured
      assert log.metadata["entity_type"] == "event"
      assert log.metadata["entity_name"] == "Metadata Test Event"
      assert log.metadata["external_id"] == "meta_456"
      assert log.metadata["venue_name"] == "Metadata Test Venue"
    end
  end

  # Test helper functions

  defp create_test_source(name \\ "test_source") do
    unique_slug = "#{name}_#{System.unique_integer([:positive])}"

    %EventasaurusDiscovery.Sources.Source{}
    |> EventasaurusDiscovery.Sources.Source.changeset(%{
      name: name,
      slug: unique_slug
    })
    |> Repo.insert!()
  end

  defp count_logs(source) do
    from(l in EventasaurusDiscovery.ScraperProcessingLogs.ScraperProcessingLog,
      where: l.source_id == ^source.id,
      select: count(l.id)
    )
    |> Repo.one()
  end
end
