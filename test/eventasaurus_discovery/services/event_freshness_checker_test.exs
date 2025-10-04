defmodule EventasaurusDiscovery.Services.EventFreshnessCheckerTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource

  describe "filter_events_needing_processing/3" do
    setup do
      # Create a test source
      source = insert(:public_event_source_type, name: "Test Source")
      {:ok, source: source}
    end

    test "filters out events seen within threshold", %{source: source} do
      # Create an event source seen 1 hour ago (within 7 day threshold)
      recent_datetime = DateTime.add(DateTime.utc_now(), -1, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "test_123",
        last_seen_at: recent_datetime
      )

      # Create events to check
      events = [
        # Should be filtered out (recent)
        %{"external_id" => "test_123"},
        # Should be included (not seen)
        %{"external_id" => "test_456"}
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      assert length(result) == 1
      assert hd(result)["external_id"] == "test_456"
    end

    test "includes events seen outside threshold", %{source: source} do
      # Create an event source seen 8 days ago (outside 7 day threshold)
      old_datetime = DateTime.add(DateTime.utc_now(), -8 * 24, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "test_old",
        last_seen_at: old_datetime
      )

      events = [
        %{"external_id" => "test_old"}
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      assert length(result) == 1
      assert hd(result)["external_id"] == "test_old"
    end

    test "handles empty event list", %{source: source} do
      result = EventFreshnessChecker.filter_events_needing_processing([], source.id)

      assert result == []
    end

    test "handles events without external_id", %{source: source} do
      events = [
        %{"title" => "Event without external_id"}
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Events without external_id are included (safe default)
      assert length(result) == 1
    end

    test "works with atom key external_id", %{source: source} do
      # Create event source
      recent_datetime = DateTime.add(DateTime.utc_now(), -1, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "test_atom",
        last_seen_at: recent_datetime
      )

      events = [
        # Atom key - should be filtered
        %{external_id: "test_atom"},
        # Atom key - should be included
        %{external_id: "test_new"}
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      assert length(result) == 1
      assert hd(result).external_id == "test_new"
    end

    test "respects custom threshold override", %{source: source} do
      # Create event source seen 2 hours ago
      datetime = DateTime.add(DateTime.utc_now(), -2, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "test_custom",
        last_seen_at: datetime
      )

      events = [%{"external_id" => "test_custom"}]

      # With 1 hour threshold, should filter out (2 hours < default)
      result_short = EventFreshnessChecker.filter_events_needing_processing(events, source.id, 1)
      # Included because 2h > 1h threshold
      assert length(result_short) == 1

      # With 3 hour threshold, should filter out (2 hours < 3)
      result_long = EventFreshnessChecker.filter_events_needing_processing(events, source.id, 3)
      # Filtered because 2h < 3h threshold
      assert length(result_long) == 0
    end

    test "handles batch of mixed events", %{source: source} do
      # Create some recent event sources
      recent = DateTime.add(DateTime.utc_now(), -1, :hour)
      old = DateTime.add(DateTime.utc_now(), -8 * 24, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "recent_1",
        last_seen_at: recent
      )

      insert(:public_event_source,
        source_id: source.id,
        external_id: "old_1",
        last_seen_at: old
      )

      events = [
        # Filter out
        %{"external_id" => "recent_1"},
        # Include
        %{"external_id" => "old_1"},
        # Include (never seen)
        %{"external_id" => "new_1"},
        # Include (no external_id)
        %{"title" => "no_id"}
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      assert length(result) == 3
      external_ids = Enum.map(result, & &1["external_id"])
      assert "old_1" in external_ids
      assert "new_1" in external_ids
      refute "recent_1" in external_ids
    end
  end

  describe "get_threshold/0" do
    test "returns configured threshold" do
      threshold = EventFreshnessChecker.get_threshold()

      # Should return default of 168 hours (7 days)
      assert threshold == 168
    end
  end
end
