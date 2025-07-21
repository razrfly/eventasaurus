defmodule EventasaurusApp.Events.DeleteTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.{Events, Repo}
  alias EventasaurusApp.Events.{Event, Delete, HardDelete, SoftDelete}
  alias EventasaurusApp.Accounts.User
  
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

  describe "delete_event/3" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "performs hard deletion when event is eligible", %{user: user, event: event} do
      # Event with no participants should be eligible for hard delete
      assert {:ok, :hard_deleted} = Delete.delete_event(event.id, user.id, "Test deletion")
      
      # Verify event is gone from database
      assert Events.get_event(event.id) == nil
      assert Events.get_event(event.id, include_deleted: true) == nil
    end

    test "performs soft deletion when event has participants", %{user: user, event: event} do
      # Add a participant to make it ineligible for hard delete
      _participant = event_participant_fixture(%{event: event})
      
      assert {:ok, :soft_deleted} = Delete.delete_event(event.id, user.id, "Test deletion")
      
      # Verify event is soft deleted but still in database
      assert Events.get_event(event.id) == nil
      assert Events.get_event(event.id, include_deleted: true) != nil
    end

    test "returns error when event not found" do
      user = user_fixture()
      
      assert {:error, :event_not_found} = Delete.delete_event(999, user.id, "Test deletion")
    end

    test "returns error when user not found", %{event: event} do
      assert {:error, :user_not_found} = Delete.delete_event(event.id, 999, "Test deletion")
    end

    test "returns error when user lacks permission", %{event: event} do
      other_user = user_fixture()
      
      assert {:error, :permission_denied} = Delete.delete_event(event.id, other_user.id, "Test deletion")
    end

    test "returns error when reason is invalid", %{user: user, event: event} do
      assert {:error, :invalid_reason} = Delete.delete_event(event.id, user.id, nil)
      assert {:error, :invalid_reason} = Delete.delete_event(event.id, user.id, 123)
    end

    test "falls back to soft delete when hard delete fails", %{user: user, event: event} do
      # Update event to be very old (should fail hard delete age check)
      old_date = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
              |> DateTime.to_naive()
              |> NaiveDateTime.truncate(:second)
      
      {:ok, old_event} = event
      |> Event.changeset(%{})
      |> Ecto.Changeset.put_change(:inserted_at, old_date)
      |> Repo.update()

      # Should fall back to soft delete
      assert {:ok, :soft_deleted} = Delete.delete_event(old_event.id, user.id, "Test deletion")
      
      # Verify it was soft deleted
      assert Events.get_event(old_event.id) == nil
      assert Events.get_event(old_event.id, include_deleted: true) != nil
    end
  end

  describe "deletion_method/2" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "returns :hard for eligible events", %{user: user, event: event} do
      assert :hard = Delete.deletion_method(event, user)
    end

    test "returns :soft for ineligible events", %{user: user, event: event} do
      # Add a participant to make it ineligible
      _participant = event_participant_fixture(%{event: event})
      
      # Need to reload event to ensure fresh data
      event = Events.get_event!(event.id)
      assert :soft = Delete.deletion_method(event, user)
    end
  end

  describe "soft_delete_reason/2" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "returns nil for eligible events", %{user: user, event: event} do
      assert Delete.soft_delete_reason(event, user) == nil
    end

    test "returns reason for ineligible events", %{user: user, event: event} do
      # Add a participant to make it ineligible
      _participant = event_participant_fixture(%{event: event})
      
      reason = Delete.soft_delete_reason(event, user)
      assert reason == "Event has user participants and cannot be permanently deleted"
    end
  end

  describe "audit logging" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    @tag capture_log: true
    test "logs successful hard deletion", %{user: user, event: event} do
      import ExUnit.CaptureLog

      log = capture_log(fn ->
        assert {:ok, :hard_deleted} = Delete.delete_event(event.id, user.id, "Audit test")
      end)

      assert log =~ "Event deletion attempt successful"
      assert log =~ "Event hard deleted"
      assert log =~ "event_id=#{event.id}"
      assert log =~ "user_id=#{user.id}"
    end

    @tag capture_log: true
    test "logs successful soft deletion", %{user: user, event: event} do
      import ExUnit.CaptureLog

      # Make ineligible for hard delete
      _participant = event_participant_fixture(%{event: event})

      log = capture_log(fn ->
        assert {:ok, :soft_deleted} = Delete.delete_event(event.id, user.id, "Audit test")
      end)

      assert log =~ "Event deletion attempt successful"
      assert log =~ "Event soft deleted"
      assert log =~ "event_id=#{event.id}"
      assert log =~ "user_id=#{user.id}"
    end

    @tag capture_log: true
    test "logs failed deletion attempts", %{user: user} do
      import ExUnit.CaptureLog

      log = capture_log(fn ->
        assert {:error, :event_not_found} = Delete.delete_event(999, user.id, "Audit test")
      end)

      assert log =~ "Event deletion attempt failed"
      assert log =~ "error: :event_not_found"
    end

    @tag capture_log: true
    test "logs hard delete fallback to soft delete", %{user: user, event: event} do
      import ExUnit.CaptureLog

      # Update event to be very old (should fail hard delete age check)
      old_date = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
              |> DateTime.to_naive()
              |> NaiveDateTime.truncate(:second)
      
      {:ok, old_event} = event
      |> Event.changeset(%{})
      |> Ecto.Changeset.put_change(:inserted_at, old_date)
      |> Repo.update()

      log = capture_log(fn ->
        assert {:ok, :soft_deleted} = Delete.delete_event(old_event.id, user.id, "Fallback test")
      end)

      assert log =~ "Hard delete failed, falling back to soft delete"
      assert log =~ "error=too_old"
      assert log =~ "Event soft deleted"
    end
  end

  describe "Events context integration" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "Events.delete_event/3 delegates to Delete module", %{user: user, event: event} do
      assert {:ok, :hard_deleted} = Events.delete_event(event.id, user.id, "Integration test")
      
      # Verify event is gone
      assert Events.get_event(event.id) == nil
    end

    test "Events.deletion_method/2 delegates to Delete module", %{user: user, event: event} do
      assert :hard = Events.deletion_method(event, user)
    end

    test "Events.soft_delete_reason/2 delegates to Delete module", %{user: user, event: event} do
      assert Events.soft_delete_reason(event, user) == nil
    end
  end

  describe "edge cases" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "handles double deletion gracefully", %{user: user, event: event} do
      # First deletion (hard delete)
      assert {:ok, :hard_deleted} = Delete.delete_event(event.id, user.id, "First deletion")
      
      # Second deletion attempt should fail with event_not_found
      assert {:error, :event_not_found} = Delete.delete_event(event.id, user.id, "Second deletion")
    end

    test "handles soft-deleted event deletion attempts", %{user: user, event: event} do
      # Make ineligible for hard delete
      _participant = event_participant_fixture(%{event: event})
      
      # First deletion (soft delete)
      assert {:ok, :soft_deleted} = Delete.delete_event(event.id, user.id, "First deletion")
      
      # Second deletion attempt should fail
      # Since get_event_safely excludes soft-deleted by default
      assert {:error, :event_not_found} = Delete.delete_event(event.id, user.id, "Second deletion")
    end

    test "handles concurrent organizer scenarios", %{event: event} do
      # Create multiple organizers
      organizer1 = user_fixture()
      organizer2 = user_fixture()
      
      Events.add_user_to_event(event, organizer1)
      Events.add_user_to_event(event, organizer2)
      
      # Both organizers should be able to delete
      assert {:ok, :hard_deleted} = Delete.delete_event(event.id, organizer1.id, "Organizer 1 deletion")
    end

    test "handles string IDs", %{user: user, event: event} do
      # Should handle string IDs gracefully
      assert {:ok, :hard_deleted} = Delete.delete_event("#{event.id}", "#{user.id}", "String ID test")
    end
  end
end