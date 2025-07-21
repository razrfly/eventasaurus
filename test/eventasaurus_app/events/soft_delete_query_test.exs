defmodule EventasaurusApp.Events.SoftDeleteQueryTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.{Events, Repo}
  alias EventasaurusApp.Events.{Event, SoftDelete}
  
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

  describe "soft delete filtering in queries" do
    setup do
      user = user_fixture()
      active_event = event_fixture(organizers: [user], title: "Active Event")
      deleted_event = event_fixture(organizers: [user], title: "Deleted Event")
      
      # Soft delete the second event
      {:ok, _} = SoftDelete.soft_delete_event(deleted_event.id, "Test deletion", user.id)
      
      %{user: user, active_event: active_event, deleted_event: deleted_event}
    end

    test "list_events excludes soft-deleted events by default", %{active_event: active} do
      events = Events.list_events()
      
      assert length(events) == 1
      assert hd(events).id == active.id
    end

    test "list_events includes soft-deleted events with option", %{active_event: active, deleted_event: deleted} do
      events = Events.list_events(include_deleted: true)
      
      assert length(events) == 2
      event_ids = Enum.map(events, & &1.id)
      assert active.id in event_ids
      assert deleted.id in event_ids
    end

    test "get_event returns nil for soft-deleted events by default", %{deleted_event: deleted} do
      assert Events.get_event(deleted.id) == nil
    end

    test "get_event returns soft-deleted events with option", %{deleted_event: deleted} do
      event = Events.get_event(deleted.id, include_deleted: true)
      assert event.id == deleted.id
      assert event.deleted_at != nil
    end

    test "get_event! raises for soft-deleted events", %{deleted_event: deleted} do
      assert_raise Ecto.NoResultsError, fn ->
        Events.get_event!(deleted.id)
      end
    end

    test "get_event_by_slug excludes soft-deleted events by default", %{deleted_event: deleted} do
      assert Events.get_event_by_slug(deleted.slug) == nil
    end

    test "get_event_by_slug includes soft-deleted events with option", %{deleted_event: deleted} do
      event = Events.get_event_by_slug(deleted.slug, include_deleted: true)
      assert event.id == deleted.id
    end

    test "list_events_by_user excludes soft-deleted events by default", %{user: user, active_event: active} do
      events = Events.list_events_by_user(user)
      
      assert length(events) == 1
      assert hd(events).id == active.id
    end

    test "list_events_by_user includes soft-deleted events with option", %{user: user, active_event: active, deleted_event: deleted} do
      events = Events.list_events_by_user(user, include_deleted: true)
      
      assert length(events) == 2
      event_ids = Enum.map(events, & &1.id)
      assert active.id in event_ids
      assert deleted.id in event_ids
    end

    test "list_active_events excludes soft-deleted events", %{active_event: active} do
      events = Events.list_active_events()
      
      # Filter to just our test events
      test_events = Enum.filter(events, & &1.id == active.id)
      assert length(test_events) == 1
    end

    test "list_threshold_events excludes soft-deleted threshold events", %{user: user} do
      # Create threshold events
      active_threshold = event_fixture(
        organizers: [user], 
        title: "Active Threshold", 
        status: :threshold,
        threshold_type: "revenue",
        threshold_revenue_cents: 10000
      )
      
      deleted_threshold = event_fixture(
        organizers: [user], 
        title: "Deleted Threshold", 
        status: :threshold,
        threshold_type: "revenue",
        threshold_revenue_cents: 10000
      )
      
      # Soft delete one
      {:ok, _} = SoftDelete.soft_delete_event(deleted_threshold.id, "Test deletion", user.id)
      
      # Check filtering
      events = Events.list_threshold_events()
      threshold_ids = Enum.map(events, & &1.id)
      
      assert active_threshold.id in threshold_ids
      refute deleted_threshold.id in threshold_ids
      
      # Check with include_deleted
      all_events = Events.list_threshold_events(include_deleted: true)
      all_ids = Enum.map(all_events, & &1.id)
      
      assert active_threshold.id in all_ids
      assert deleted_threshold.id in all_ids
    end
  end

  describe "soft delete filtering in participant queries" do
    setup do
      organizer = user_fixture()
      participant = user_fixture()
      
      active_event = event_fixture(organizers: [organizer], title: "Active with Participants")
      deleted_event = event_fixture(organizers: [organizer], title: "Deleted with Participants")
      
      # Add participants to both events
      _active_participant = event_participant_fixture(%{event: active_event, user: participant})
      _deleted_participant = event_participant_fixture(%{event: deleted_event, user: participant})
      
      # Soft delete one event
      {:ok, _} = SoftDelete.soft_delete_event(deleted_event.id, "Test deletion", organizer.id)
      
      %{
        organizer: organizer,
        participant: participant,
        active_event: active_event,
        deleted_event: deleted_event
      }
    end

    test "list_events_with_participation excludes soft-deleted events", %{participant: participant, active_event: active} do
      events = Events.list_events_with_participation(participant)
      
      assert length(events) == 1
      assert hd(events).id == active.id
    end

    test "list_events_with_participation includes soft-deleted with option", %{participant: participant, active_event: active, deleted_event: deleted} do
      events = Events.list_events_with_participation(participant, include_deleted: true)
      
      assert length(events) == 2
      event_ids = Enum.map(events, & &1.id)
      assert active.id in event_ids
      assert deleted.id in event_ids
    end

    test "list_organizer_events_with_participants excludes soft-deleted", %{organizer: organizer, active_event: active} do
      events = Events.list_organizer_events_with_participants(organizer)
      
      assert length(events) == 1
      assert hd(events).id == active.id
    end

    test "get_historical_participants excludes participants from soft-deleted events", %{organizer: organizer, participant: participant} do
      participants = Events.get_historical_participants(organizer)
      
      # Should still find the participant since they're in the active event
      participant_ids = Enum.map(participants, & &1.user_id)
      assert participant.id in participant_ids
      
      # But the event_ids should only include the active event
      participant_data = Enum.find(participants, & &1.user_id == participant.id)
      assert length(participant_data.event_ids) == 1
    end
  end

  describe "soft delete filtering in poll queries" do
    setup do
      user = user_fixture()
      active_event = event_fixture(organizers: [user], title: "Active with Poll")
      deleted_event = event_fixture(organizers: [user], title: "Deleted with Poll")
      
      # Create polls for both events
      {:ok, active_poll} = Events.create_poll(%{
        event_id: active_event.id,
        poll_type: "venue_selection",
        title: "Active Poll",
        created_by_id: user.id
      })
      
      {:ok, deleted_poll} = Events.create_poll(%{
        event_id: deleted_event.id,
        poll_type: "venue_selection", 
        title: "Deleted Poll",
        created_by_id: user.id
      })
      
      # Soft delete one event
      {:ok, _} = SoftDelete.soft_delete_event(deleted_event.id, "Test deletion", user.id)
      
      %{
        user: user,
        active_event: active_event,
        deleted_event: deleted_event,
        active_poll: active_poll,
        deleted_poll: deleted_poll
      }
    end

    test "get_event_poll excludes polls from soft-deleted events", %{active_event: active, deleted_event: deleted} do
      # Should find poll for active event
      poll = Events.get_event_poll(active, "venue_selection")
      assert poll != nil
      assert poll.title == "Active Poll"
      
      # Should not find poll for deleted event
      assert Events.get_event_poll(deleted, "venue_selection") == nil
    end

    test "get_event_poll includes polls from soft-deleted events with option", %{deleted_event: deleted} do
      poll = Events.get_event_poll(deleted, "venue_selection", include_deleted: true)
      assert poll != nil
      assert poll.title == "Deleted Poll"
    end
  end

  describe "soft delete filtering with complex queries" do
    setup do
      organizer = user_fixture()
      
      # Create multiple events with different states
      past_event = event_fixture(
        organizers: [organizer],
        title: "Past Event",
        ends_at: DateTime.add(DateTime.utc_now(), -7, :day)
      )
      
      future_event = event_fixture(
        organizers: [organizer],
        title: "Future Event",
        start_at: DateTime.add(DateTime.utc_now(), 7, :day)
      )
      
      deleted_past = event_fixture(
        organizers: [organizer],
        title: "Deleted Past",
        ends_at: DateTime.add(DateTime.utc_now(), -7, :day)
      )
      
      # Soft delete one
      {:ok, _} = SoftDelete.soft_delete_event(deleted_past.id, "Test deletion", organizer.id)
      
      %{
        organizer: organizer,
        past_event: past_event,
        future_event: future_event,
        deleted_past: deleted_past
      }
    end

    test "list_ended_events excludes soft-deleted events", %{past_event: past} do
      events = Events.list_ended_events()
      
      # Filter to our test events
      test_events = Enum.filter(events, & &1.title in ["Past Event", "Deleted Past"])
      
      assert length(test_events) == 1
      assert hd(test_events).id == past.id
    end

    test "list_ended_events includes soft-deleted with option", %{past_event: past, deleted_past: deleted} do
      events = Events.list_ended_events(include_deleted: true)
      
      # Filter to our test events
      test_events = Enum.filter(events, & &1.title in ["Past Event", "Deleted Past"])
      
      assert length(test_events) == 2
      event_ids = Enum.map(test_events, & &1.id)
      assert past.id in event_ids
      assert deleted.id in event_ids
    end
  end
end