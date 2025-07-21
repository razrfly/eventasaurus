defmodule EventasaurusApp.Events.HardDeleteTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.{Events, Repo}
  alias EventasaurusApp.Events.{Event, HardDelete}
  
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

  describe "eligible_for_hard_delete?/3" do
    setup do
      # Create test user and event using fixtures
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "returns ok for eligible events", %{user: user, event: event} do
      assert {:ok, ^event} = HardDelete.eligible_for_hard_delete?(event.id, user.id)
    end

    test "returns error when event has participants", %{user: user, event: event} do
      # Add participant to event using fixture
      _participant = event_participant_fixture(%{event: event})

      assert {:error, :has_participants} = HardDelete.eligible_for_hard_delete?(event.id, user.id)
    end

    test "returns error when user is not an organizer", %{event: event} do
      # Create another user who is not an organizer
      other_user = user_fixture()

      assert {:error, :not_owner} = HardDelete.eligible_for_hard_delete?(event.id, other_user.id)
    end

    test "returns error when event is too old", %{user: user, event: event} do
      # Update event to be older than the default limit (90 days)
      old_date = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)
              |> DateTime.to_naive()
              |> NaiveDateTime.truncate(:second)
      
      {:ok, old_event} = event
      |> Event.changeset(%{})
      |> Ecto.Changeset.put_change(:inserted_at, old_date)
      |> Repo.update()

      assert {:error, :too_old} = HardDelete.eligible_for_hard_delete?(old_event.id, user.id)
    end

    test "respects custom age limits", %{user: user, event: event} do
      # Update event to be 10 days old
      old_date = DateTime.add(DateTime.utc_now(), -10 * 24 * 60 * 60, :second)
              |> DateTime.to_naive()
              |> NaiveDateTime.truncate(:second)
      
      {:ok, old_event} = event
      |> Event.changeset(%{})
      |> Ecto.Changeset.put_change(:inserted_at, old_date)
      |> Repo.update()

      # Should fail with 5-day limit
      assert {:error, :too_old} = HardDelete.eligible_for_hard_delete?(old_event.id, user.id, max_age_days: 5)
      
      # Should pass with 30-day limit
      assert {:ok, ^old_event} = HardDelete.eligible_for_hard_delete?(old_event.id, user.id, max_age_days: 30)
    end
  end

  describe "hard_delete_event/3" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "successfully deletes eligible event", %{user: user, event: event} do
      assert {:ok, deleted_event} = HardDelete.hard_delete_event(event.id, user.id)
      assert deleted_event.id == event.id
      
      # Verify event is gone from database
      assert Events.get_event(event.id) == nil
    end

    test "returns error for ineligible event", %{user: user, event: event} do
      # Add a participant to make it ineligible
      _participant = event_participant_fixture(%{event: event})

      assert {:error, :has_participants} = HardDelete.hard_delete_event(event.id, user.id)
      
      # Verify event still exists
      assert Events.get_event(event.id) != nil
    end
  end

  describe "get_ineligibility_reason/3" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])

      %{user: user, event: event}
    end

    test "returns nil for eligible events", %{user: user, event: event} do
      assert HardDelete.get_ineligibility_reason(event.id, user.id) == nil
    end

    test "returns descriptive reason for ineligible events", %{user: user, event: event} do
      # Add a participant
      _participant = event_participant_fixture(%{event: event})

      reason = HardDelete.get_ineligibility_reason(event.id, user.id)
      assert reason == "Event has user participants and cannot be permanently deleted"
    end
  end
end