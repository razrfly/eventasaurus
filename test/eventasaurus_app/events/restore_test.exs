defmodule EventasaurusApp.Events.RestoreTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.{Events, Repo}
  alias EventasaurusApp.Events.{Event, Restore, SoftDelete}
  alias EventasaurusApp.Accounts.User
  
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

  describe "restore_event/2" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      
      # Create some associated records
      participant = event_participant_fixture(%{event: event})
      poll = poll_fixture(%{event: event, user: user})
      
      # Soft delete the event
      {:ok, _} = SoftDelete.soft_delete_event(event.id, "Test deletion", user.id)
      
      %{user: user, event: event, participant: participant, poll: poll}
    end

    test "successfully restores soft-deleted event with all associations", %{user: user, event: event} do
      # Verify event is soft-deleted
      assert Events.get_event(event.id) == nil
      assert Events.get_event(event.id, include_deleted: true) != nil
      
      # Restore the event
      assert {:ok, restored_event} = Restore.restore_event(event.id, user.id)
      
      # Verify event is restored
      assert restored_event.id == event.id
      assert restored_event.deleted_at == nil
      assert restored_event.deletion_reason == nil
      assert restored_event.deleted_by_user_id == nil
      
      # Verify event is accessible again
      assert Events.get_event(event.id) != nil
    end

    test "restores associated records", %{user: user, event: event} do
      # Count soft-deleted associated records before restoration
      soft_deleted_participants = Repo.aggregate(
        from(ep in EventasaurusApp.Events.EventParticipant, 
             where: ep.event_id == ^event.id and not is_nil(ep.deleted_at)),
        :count
      )
      
      soft_deleted_polls = Repo.aggregate(
        from(p in EventasaurusApp.Events.Poll,
             where: p.event_id == ^event.id and not is_nil(p.deleted_at)),
        :count
      )
      
      assert soft_deleted_participants > 0
      assert soft_deleted_polls > 0
      
      # Restore the event
      assert {:ok, _} = Restore.restore_event(event.id, user.id)
      
      # Verify associated records are restored
      restored_participants = Repo.aggregate(
        from(ep in EventasaurusApp.Events.EventParticipant,
             where: ep.event_id == ^event.id and is_nil(ep.deleted_at)),
        :count
      )
      
      restored_polls = Repo.aggregate(
        from(p in EventasaurusApp.Events.Poll,
             where: p.event_id == ^event.id and is_nil(p.deleted_at)),
        :count
      )
      
      assert restored_participants == soft_deleted_participants
      assert restored_polls == soft_deleted_polls
    end

    test "returns error when event not found", %{user: user} do
      assert {:error, :event_not_found} = Restore.restore_event(999, user.id)
    end

    test "returns error when user not found", %{event: event} do
      assert {:error, :user_not_found} = Restore.restore_event(event.id, 999)
    end

    test "returns error when event is not soft-deleted", %{user: user} do
      active_event = event_fixture(organizers: [user])
      
      assert {:error, :event_not_deleted} = Restore.restore_event(active_event.id, user.id)
    end

    test "returns error when user lacks permission", %{event: event} do
      other_user = user_fixture()
      
      assert {:error, :permission_denied} = Restore.restore_event(event.id, other_user.id)
    end

    test "returns error when restoration window has expired", %{user: user, event: event} do
      # Mock an old deletion date (more than 90 days ago)
      old_date = DateTime.add(DateTime.utc_now(), -95 * 24 * 60 * 60, :second)
      
      {:ok, _} = Repo.update_all(
        from(e in Event, where: e.id == ^event.id),
        set: [deleted_at: old_date]
      )
      
      assert {:error, :restoration_window_expired} = Restore.restore_event(event.id, user.id)
    end

    test "returns error when slug conflict exists", %{user: user, event: event} do
      # Create another event with the same slug
      conflicting_event = event_fixture(organizers: [user], slug: event.slug)
      
      assert {:error, :slug_conflict} = Restore.restore_event(event.id, user.id)
      
      # Cleanup
      Repo.delete!(conflicting_event)
    end

    test "handles restoration within transaction", %{user: user, event: event} do
      # Mock a failure in associated record restoration by making one of the updates fail
      # This is a bit tricky to test without modifying the implementation
      # For now, we'll just verify that successful restoration is atomic
      
      assert {:ok, restored_event} = Restore.restore_event(event.id, user.id)
      assert restored_event.deleted_at == nil
      
      # If this succeeded, all associated records should be restored too
      participant_count = Repo.aggregate(
        from(ep in EventasaurusApp.Events.EventParticipant,
             where: ep.event_id == ^event.id and is_nil(ep.deleted_at)),
        :count
      )
      
      assert participant_count > 0
    end
  end

  describe "eligible_for_restoration?/1" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      
      # Soft delete the event
      {:ok, _} = SoftDelete.soft_delete_event(event.id, "Test deletion", user.id)
      
      %{user: user, event: event}
    end

    test "returns {:ok, event} for eligible soft-deleted event", %{event: event} do
      assert {:ok, returned_event} = Restore.eligible_for_restoration?(event.id)
      assert returned_event.id == event.id
    end

    test "returns error for non-existent event" do
      assert {:error, :event_not_found} = Restore.eligible_for_restoration?(999)
    end

    test "returns error for active event" do
      active_event = event_fixture()
      
      assert {:error, :event_not_deleted} = Restore.eligible_for_restoration?(active_event.id)
    end

    test "returns error for event outside restoration window", %{event: event} do
      # Set deletion date to more than 90 days ago
      old_date = DateTime.add(DateTime.utc_now(), -95 * 24 * 60 * 60, :second)
      
      {:ok, _} = Repo.update_all(
        from(e in Event, where: e.id == ^event.id),
        set: [deleted_at: old_date]
      )
      
      assert {:error, :restoration_window_expired} = Restore.eligible_for_restoration?(event.id)
    end
  end

  describe "get_restoration_stats/1" do
    test "returns basic statistics structure" do
      stats = Restore.get_restoration_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :total_restored)
      assert Map.has_key?(stats, :restored_in_period)
      assert Map.has_key?(stats, :period_days)
      assert Map.has_key?(stats, :cutoff_date)
      
      assert stats.period_days == 30 # default
    end

    test "respects custom period" do
      stats = Restore.get_restoration_stats(days_back: 7)
      
      assert stats.period_days == 7
    end
  end

  describe "audit logging" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      
      # Soft delete the event
      {:ok, _} = SoftDelete.soft_delete_event(event.id, "Test deletion", user.id)
      
      %{user: user, event: event}
    end

    @tag capture_log: true
    test "logs successful restoration", %{user: user, event: event} do
      import ExUnit.CaptureLog

      log = capture_log(fn ->
        assert {:ok, _} = Restore.restore_event(event.id, user.id)
      end)

      assert log =~ "Event restoration attempt successful"
      assert log =~ "Starting restoration process"
      assert log =~ "Event restored successfully"
      assert log =~ "event_id=#{event.id}"
      assert log =~ "user_id=#{user.id}"
    end

    @tag capture_log: true
    test "logs failed restoration attempts", %{event: event} do
      import ExUnit.CaptureLog

      log = capture_log(fn ->
        assert {:error, :user_not_found} = Restore.restore_event(event.id, 999)
      end)

      assert log =~ "Event restoration attempt failed"
      assert log =~ "error: :user_not_found"
    end

    @tag capture_log: true
    test "logs restoration of associated records", %{user: user, event: event} do
      import ExUnit.CaptureLog

      log = capture_log(fn ->
        assert {:ok, _} = Restore.restore_event(event.id, user.id)
      end)

      # Should log restoration of each type of associated record
      assert log =~ "Restored"
      assert log =~ "event participants"
      assert log =~ "polls"
    end
  end

  describe "Events context integration" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      
      # Soft delete the event
      {:ok, _} = SoftDelete.soft_delete_event(event.id, "Test deletion", user.id)
      
      %{user: user, event: event}
    end

    test "Events.restore_event/2 delegates to Restore module", %{user: user, event: event} do
      assert {:ok, restored_event} = Events.restore_event(event.id, user.id)
      
      assert restored_event.id == event.id
      assert restored_event.deleted_at == nil
    end

    test "Events.eligible_for_restoration?/1 delegates to Restore module", %{event: event} do
      assert {:ok, returned_event} = Events.eligible_for_restoration?(event.id)
      assert returned_event.id == event.id
    end

    test "Events.get_restoration_stats/1 delegates to Restore module" do
      stats = Events.get_restoration_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :total_restored)
    end
  end

  describe "edge cases and error handling" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      
      %{user: user, event: event}
    end

    test "handles double restoration gracefully", %{user: user, event: event} do
      # Soft delete the event
      {:ok, _} = SoftDelete.soft_delete_event(event.id, "Test deletion", user.id)
      
      # First restoration
      assert {:ok, _} = Restore.restore_event(event.id, user.id)
      
      # Second restoration attempt should fail
      assert {:error, :event_not_deleted} = Restore.restore_event(event.id, user.id)
    end

    test "handles string IDs", %{user: user, event: event} do
      # Soft delete the event
      {:ok, _} = SoftDelete.soft_delete_event(event.id, "Test deletion", user.id)
      
      # Should handle string IDs gracefully
      assert {:ok, _} = Restore.restore_event("#{event.id}", "#{user.id}")
    end

    test "handles concurrent organizer scenarios", %{event: event} do
      # Create multiple organizers
      organizer1 = user_fixture()
      organizer2 = user_fixture()
      
      Events.add_user_to_event(event, organizer1)
      Events.add_user_to_event(event, organizer2)
      
      # Soft delete the event
      {:ok, _} = SoftDelete.soft_delete_event(event.id, "Test deletion", organizer1.id)
      
      # Both organizers should be able to restore
      assert {:ok, _} = Restore.restore_event(event.id, organizer2.id)
    end
  end
end