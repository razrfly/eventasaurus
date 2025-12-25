defmodule EventasaurusDiscovery.Services.EventFreshnessCheckerTest do
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusDiscovery.Services.EventFreshnessChecker

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

  describe "get_threshold_for_slug/1" do
    test "returns override threshold for kino-krakow" do
      threshold = EventFreshnessChecker.get_threshold_for_slug("kino-krakow")

      # Should return 24 hours as configured in test.exs
      assert threshold == 24
    end

    test "returns override threshold for cinema-city" do
      threshold = EventFreshnessChecker.get_threshold_for_slug("cinema-city")

      # Should return 48 hours as configured in test.exs
      assert threshold == 48
    end

    test "returns default threshold for unknown source" do
      threshold = EventFreshnessChecker.get_threshold_for_slug("unknown-source")

      # Should fallback to default 168 hours
      assert threshold == 168
    end

    test "returns default threshold for nil slug" do
      threshold = EventFreshnessChecker.get_threshold_for_slug("")

      # Should fallback to default 168 hours
      assert threshold == 168
    end
  end

  describe "get_threshold_for_source/1" do
    test "returns override threshold for kino-krakow source" do
      # Create source with kino-krakow slug
      source = insert(:public_event_source_type, slug: "kino-krakow", name: "Kino Krakow")

      threshold = EventFreshnessChecker.get_threshold_for_source(source.id)

      # Should return 24 hours
      assert threshold == 24
    end

    test "returns override threshold for cinema-city source" do
      # Create source with cinema-city slug
      source = insert(:public_event_source_type, slug: "cinema-city", name: "Cinema City")

      threshold = EventFreshnessChecker.get_threshold_for_source(source.id)

      # Should return 48 hours
      assert threshold == 48
    end

    test "returns default threshold for source without override" do
      # Create source with regular slug
      source = insert(:public_event_source_type, slug: "bandsintown", name: "Bandsintown")

      threshold = EventFreshnessChecker.get_threshold_for_source(source.id)

      # Should return default 168 hours
      assert threshold == 168
    end

    test "returns default threshold and logs warning for missing source" do
      # Use non-existent source ID
      threshold = EventFreshnessChecker.get_threshold_for_source(99999)

      # Should fallback to default 168 hours
      assert threshold == 168
    end
  end

  describe "filter_events_needing_processing/3 with source-specific thresholds" do
    test "uses source-specific threshold for kino-krakow" do
      # Create kino-krakow source
      source = insert(:public_event_source_type, slug: "kino-krakow", name: "Kino Krakow")

      # Create event source seen 12 hours ago
      # Within 24h threshold for kino-krakow, so should be filtered
      datetime = DateTime.add(DateTime.utc_now(), -12, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "kk_event_1",
        last_seen_at: datetime
      )

      events = [%{"external_id" => "kk_event_1"}]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be filtered out (12h < 24h threshold)
      assert length(result) == 0
    end

    test "processes stale kino-krakow events outside 24h threshold" do
      # Create kino-krakow source
      source = insert(:public_event_source_type, slug: "kino-krakow", name: "Kino Krakow")

      # Create event source seen 30 hours ago
      # Outside 24h threshold for kino-krakow, so should be processed
      datetime = DateTime.add(DateTime.utc_now(), -30, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "kk_event_old",
        last_seen_at: datetime
      )

      events = [%{"external_id" => "kk_event_old"}]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be included (30h > 24h threshold)
      assert length(result) == 1
    end

    test "uses source-specific threshold for cinema-city" do
      # Create cinema-city source
      source = insert(:public_event_source_type, slug: "cinema-city", name: "Cinema City")

      # Create event source seen 24 hours ago
      # Within 48h threshold for cinema-city, so should be filtered
      datetime = DateTime.add(DateTime.utc_now(), -24, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "cc_event_1",
        last_seen_at: datetime
      )

      events = [%{"external_id" => "cc_event_1"}]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be filtered out (24h < 48h threshold)
      assert length(result) == 0
    end

    test "processes stale cinema-city events outside 48h threshold" do
      # Create cinema-city source
      source = insert(:public_event_source_type, slug: "cinema-city", name: "Cinema City")

      # Create event source seen 50 hours ago
      # Outside 48h threshold for cinema-city, so should be processed
      datetime = DateTime.add(DateTime.utc_now(), -50, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "cc_event_old",
        last_seen_at: datetime
      )

      events = [%{"external_id" => "cc_event_old"}]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be included (50h > 48h threshold)
      assert length(result) == 1
    end

    test "uses default threshold for sources without override" do
      # Create regular source
      source = insert(:public_event_source_type, slug: "bandsintown", name: "Bandsintown")

      # Create event source seen 100 hours ago
      # Within 168h (7 day) default threshold, so should be filtered
      datetime = DateTime.add(DateTime.utc_now(), -100, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "bit_event_1",
        last_seen_at: datetime
      )

      events = [%{"external_id" => "bit_event_1"}]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be filtered out (100h < 168h default threshold)
      assert length(result) == 0
    end
  end

  describe "recurring event bypass" do
    setup do
      source = insert(:public_event_source_type, name: "Test Source")
      {:ok, source: source}
    end

    test "always processes events with recurrence_rule (string keys)", %{source: source} do
      # Create an event source seen 1 hour ago (normally would be filtered)
      recent_datetime = DateTime.add(DateTime.utc_now(), -1, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "recurring_123",
        last_seen_at: recent_datetime
      )

      # Event has recurrence_rule - should bypass freshness check
      events = [
        %{
          "external_id" => "recurring_123",
          "recurrence_rule" => %{
            "frequency" => "weekly",
            "days_of_week" => ["tuesday"],
            "time" => "19:00",
            "timezone" => "Europe/London"
          }
        }
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be included despite being recently seen (recurring bypass)
      assert length(result) == 1
      assert hd(result)["external_id"] == "recurring_123"
    end

    test "always processes events with recurrence_rule (atom keys)", %{source: source} do
      # Create an event source seen 1 hour ago (normally would be filtered)
      recent_datetime = DateTime.add(DateTime.utc_now(), -1, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "recurring_456",
        last_seen_at: recent_datetime
      )

      # Event has recurrence_rule with atom keys - should bypass freshness check
      events = [
        %{
          external_id: "recurring_456",
          recurrence_rule: %{
            "frequency" => "weekly",
            "days_of_week" => ["wednesday"],
            "time" => "20:00",
            "timezone" => "Europe/Warsaw"
          }
        }
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be included despite being recently seen (recurring bypass)
      assert length(result) == 1
      assert hd(result).external_id == "recurring_456"
    end

    test "filters single events but includes recurring events in same batch", %{source: source} do
      # Create event sources seen 1 hour ago
      recent_datetime = DateTime.add(DateTime.utc_now(), -1, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "single_event_1",
        last_seen_at: recent_datetime
      )

      insert(:public_event_source,
        source_id: source.id,
        external_id: "recurring_event_1",
        last_seen_at: recent_datetime
      )

      # Mix of single and recurring events
      events = [
        # Single event - should be filtered (no recurrence_rule)
        %{"external_id" => "single_event_1", "title" => "Concert"},
        # Recurring event - should bypass (has recurrence_rule)
        %{
          "external_id" => "recurring_event_1",
          "title" => "Weekly Trivia",
          "recurrence_rule" => %{
            "frequency" => "weekly",
            "days_of_week" => ["monday"],
            "time" => "19:00"
          }
        },
        # New event - should be included (never seen)
        %{"external_id" => "new_event_1", "title" => "New Concert"}
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should have 2 events: the recurring one and the new one
      assert length(result) == 2

      external_ids = Enum.map(result, fn e -> e["external_id"] || e[:external_id] end)
      assert "recurring_event_1" in external_ids
      assert "new_event_1" in external_ids
      refute "single_event_1" in external_ids
    end

    test "nil recurrence_rule does not trigger bypass", %{source: source} do
      # Create an event source seen 1 hour ago
      recent_datetime = DateTime.add(DateTime.utc_now(), -1, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "null_recurrence",
        last_seen_at: recent_datetime
      )

      # Event has nil recurrence_rule - should NOT bypass
      events = [
        %{"external_id" => "null_recurrence", "recurrence_rule" => nil}
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be filtered out (nil recurrence_rule doesn't bypass)
      assert length(result) == 0
    end

    test "missing recurrence_rule key does not trigger bypass", %{source: source} do
      # Create an event source seen 1 hour ago
      recent_datetime = DateTime.add(DateTime.utc_now(), -1, :hour)

      insert(:public_event_source,
        source_id: source.id,
        external_id: "no_recurrence_key",
        last_seen_at: recent_datetime
      )

      # Event has no recurrence_rule key at all - should NOT bypass
      events = [
        %{"external_id" => "no_recurrence_key", "title" => "Regular Event"}
      ]

      result = EventFreshnessChecker.filter_events_needing_processing(events, source.id)

      # Should be filtered out (no recurrence_rule means single event)
      assert length(result) == 0
    end
  end
end
