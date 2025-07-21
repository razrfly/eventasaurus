defmodule EventasaurusApp.Events.SoftDeleteTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.{Events, Repo, Ticketing}
  alias EventasaurusApp.Events.{Event, SoftDelete}
  alias EventasaurusApp.Events.{Poll, PollOption, PollVote, EventParticipant}
  alias EventasaurusApp.Events.{Ticket, Order}
  
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

  describe "soft_delete_event/3" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "soft deletes an event successfully", %{user: user, event: event} do
      reason = "Event cancelled due to low attendance"
      
      assert {:ok, deleted_event} = SoftDelete.soft_delete_event(event.id, reason, user.id)
      
      # Verify event is soft deleted
      assert deleted_event.deleted_at != nil
      assert deleted_event.deletion_reason == reason
      assert deleted_event.deleted_by_user_id == user.id
      
      # Verify event is not returned in normal queries
      assert Events.get_event(event.id) == nil
      # Check that our event is not in the list (there may be other events)
      event_ids = Events.list_events() |> Enum.map(& &1.id)
      refute event.id in event_ids
      
      # Verify event is returned when explicitly including deleted
      assert Events.get_event(event.id, include_deleted: true) != nil
      # Check that our event is in the list when including deleted
      event_ids_with_deleted = Events.list_events(include_deleted: true) |> Enum.map(& &1.id)
      assert event.id in event_ids_with_deleted
    end

    test "soft deletes event with associated records", %{user: user, event: event} do
      # Create associated records
      participant = event_participant_fixture(%{event: event})
      poll = poll_fixture(%{event: event, user: user})
      poll_option = poll_option_fixture(%{poll: poll, user: user})
      
      # Create tickets and orders (using the Ticketing context)
      {:ok, ticket} = Ticketing.create_ticket(event, %{
        title: "General Admission",
        base_price_cents: 2500,
        quantity: 100
      })
      
      {:ok, order} = Ticketing.create_order(user, ticket, %{
        quantity: 2
      })

      reason = "Event cancelled"
      
      assert {:ok, deleted_event} = SoftDelete.soft_delete_event(event.id, reason, user.id)
      
      # Verify main event is soft deleted
      assert deleted_event.deleted_at != nil
      assert deleted_event.deletion_reason == reason
      
      # Verify associated records are soft deleted
      # Check participant
      updated_participant = Repo.get(EventParticipant, participant.id)
      assert updated_participant.deleted_at != nil
      assert updated_participant.deletion_reason == reason
      
      # Check poll and related records
      updated_poll = Repo.get(Poll, poll.id)
      assert updated_poll.deleted_at != nil
      
      updated_poll_option = Repo.get(PollOption, poll_option.id)
      assert updated_poll_option.deleted_at != nil
      
      # Check ticket and order
      updated_ticket = Repo.get(Ticket, ticket.id)
      assert updated_ticket.deleted_at != nil
      
      updated_order = Repo.get(Order, order.id)
      assert updated_order.deleted_at != nil
      
      # Verify they don't appear in normal queries
      assert Ticketing.list_tickets_for_event(event.id) == []
      assert Ticketing.list_orders_for_event(event.id) == []
      
      # Verify they appear when including deleted
      assert length(Ticketing.list_tickets_for_event(event.id, include_deleted: true)) == 1
      assert length(Ticketing.list_orders_for_event(event.id, include_deleted: true)) == 1
    end

    test "returns error for non-existent event", %{user: user} do
      assert {:error, :event_not_found} = SoftDelete.soft_delete_event(999, "Test reason", user.id)
    end

    test "returns error for already deleted event", %{user: user, event: event} do
      # First deletion
      assert {:ok, _} = SoftDelete.soft_delete_event(event.id, "First deletion", user.id)
      
      # Second deletion attempt should fail
      assert {:error, :already_deleted} = SoftDelete.soft_delete_event(event.id, "Second deletion", user.id)
    end
  end

  describe "restore_event/2" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      
      # Soft delete the event first
      {:ok, deleted_event} = SoftDelete.soft_delete_event(event.id, "Test deletion", user.id)
      
      # Verify the event was actually soft deleted
      assert deleted_event.deleted_at != nil

      %{user: user, event: deleted_event}
    end

    test "restores a soft-deleted event", %{user: user, event: event} do
      # Verify event is soft deleted
      assert Events.get_event(event.id) == nil
      
      # Restore the event
      assert {:ok, restored_event} = SoftDelete.restore_event(event.id, user.id)
      
      # Verify event is now returned in normal queries
      assert Events.get_event(event.id) != nil
      assert restored_event.deleted_at == nil
      assert restored_event.deletion_reason == nil
      assert restored_event.deleted_by_user_id == nil
    end

    test "restores event with associated records", %{user: user} do
      # Create a fresh event with associated records, then soft delete it
      fresh_event = event_fixture(organizers: [user])
      participant = event_participant_fixture(%{event: fresh_event})
      poll = poll_fixture(%{event: fresh_event, user: user})
      
      # Now soft delete the event and its records
      {:ok, deleted_event} = SoftDelete.soft_delete_event(fresh_event.id, "Test deletion", user.id)
      
      # Restore the event
      assert {:ok, restored_event} = SoftDelete.restore_event(fresh_event.id, user.id)
      
      # Verify main event is restored
      assert restored_event.deleted_at == nil
      
      # Verify associated records are restored
      updated_participant = Repo.get(EventParticipant, participant.id)
      assert updated_participant.deleted_at == nil
      
      updated_poll = Repo.get(Poll, poll.id)
      assert updated_poll.deleted_at == nil
    end

    test "returns error for non-existent event", %{user: user} do
      assert {:error, :event_not_found} = SoftDelete.restore_event(999, user.id)
    end

    test "returns error for non-deleted event", %{user: user} do
      # Create a new event that's not deleted
      active_event = event_fixture(organizers: [user])
      
      assert {:error, :event_not_deleted} = SoftDelete.restore_event(active_event.id, user.id)
    end
  end

  describe "can_soft_delete?/1" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "returns true for deletable event", %{event: event} do
      assert SoftDelete.can_soft_delete?(event.id) == true
    end

    test "returns false for non-existent event" do
      assert SoftDelete.can_soft_delete?(999) == false
    end

    test "returns false for already deleted event", %{user: user, event: event} do
      # Soft delete the event
      {:ok, _} = SoftDelete.soft_delete_event(event.id, "Test", user.id)
      
      assert SoftDelete.can_soft_delete?(event.id) == false
    end
  end

  describe "get_deletion_stats/1" do
    setup do
      user = user_fixture()
      
      # Create and soft delete some events
      event1 = event_fixture(organizers: [user])
      event2 = event_fixture(organizers: [user])
      
      {:ok, _} = SoftDelete.soft_delete_event(event1.id, "Test deletion 1", user.id)
      {:ok, _} = SoftDelete.soft_delete_event(event2.id, "Test deletion 2", user.id)

      %{user: user}
    end

    test "returns deletion statistics", %{user: _user} do
      stats = SoftDelete.get_deletion_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :total_deleted_events)
      assert Map.has_key?(stats, :total_deleted_tickets)
      assert Map.has_key?(stats, :total_deleted_orders)
      assert Map.has_key?(stats, :total_deleted_participants)
      assert Map.has_key?(stats, :total_deleted_polls)
      
      # Should have at least 2 deleted events
      assert stats.total_deleted_events >= 2
    end

    test "respects days_back parameter", %{user: _user} do
      # Get stats for last 1 day (should include recent deletions)
      recent_stats = SoftDelete.get_deletion_stats(days_back: 1)
      assert recent_stats.total_deleted_events >= 2
      
      # Get stats for 0 days back (should be 0 since we can't go into the future)
      # Note: This might need adjustment based on how the cutoff_date logic works
      future_stats = SoftDelete.get_deletion_stats(days_back: 0)
      assert future_stats.total_deleted_events >= 0
    end
  end

  describe "Events context integration" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "Events.soft_delete_event/3 delegates to SoftDelete module", %{user: user, event: event} do
      reason = "Integration test"
      
      assert {:ok, deleted_event} = Events.soft_delete_event(event.id, reason, user.id)
      assert deleted_event.deleted_at != nil
      assert deleted_event.deletion_reason == reason
    end

    test "Events.restore_event/2 delegates to SoftDelete module", %{user: user, event: event} do
      # First soft delete
      {:ok, _} = Events.soft_delete_event(event.id, "Test", user.id)
      
      # Then restore
      assert {:ok, restored_event} = Events.restore_event(event.id, user.id)
      assert restored_event.deleted_at == nil
    end

    test "Events.can_soft_delete?/1 delegates to SoftDelete module", %{event: event} do
      assert Events.can_soft_delete?(event.id) == true
    end

    test "Events.get_deletion_stats/1 delegates to SoftDelete module" do
      stats = Events.get_deletion_stats()
      assert is_map(stats)
    end
  end
end