defmodule EventasaurusApp.EventsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  describe "events" do
    test "list_events/0 returns all events" do
      event = event_fixture()
      assert Events.list_events() == [event]
    end

    test "get_event!/1 returns the event with given id" do
      event = event_fixture()
      assert Events.get_event!(event.id) == event
    end

    test "create_event/1 with valid data creates a event" do
      valid_attrs = %{
        title: "Some title",
        description: "Some description",
        start_at: ~N[2024-05-21 14:20:00]
      }

      assert {:ok, %Event{} = event} = Events.create_event(valid_attrs)
      assert event.title == "Some title"
      assert event.description == "Some description"
      assert event.start_at == ~N[2024-05-21 14:20:00]
    end

    test "create_event/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Events.create_event(%{})
    end

    test "update_event/2 with valid data updates the event" do
      event = event_fixture()
      update_attrs = %{title: "Updated title"}

      assert {:ok, %Event{} = event} = Events.update_event(event, update_attrs)
      assert event.title == "Updated title"
    end

    test "delete_event/1 deletes the event" do
      event = event_fixture()
      assert {:ok, %Event{}} = Events.delete_event(event)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(event.id) end
    end
  end

  describe "process_guest_invitations/3" do
    test "successfully processes suggestion and email invitations" do
      event = event_fixture()
      organizer = user_fixture()

      # Create a historical user for suggestion
      suggested_user = user_fixture(%{email: "suggested@example.com", name: "Suggested User"})

      suggestion_structs = [
        %{
          user_id: suggested_user.id,
          recommendation_level: "recommended",
          total_score: 8.5
        }
      ]

      manual_emails = ["newuser@example.com"]
      invitation_message = "Come join us!"

      result = Events.process_guest_invitations(event, organizer,
        suggestion_structs: suggestion_structs,
        manual_emails: manual_emails,
        invitation_message: invitation_message
      )

      # Should have 2 successful invitations
      assert result.successful_invitations == 2
      assert result.skipped_duplicates == 0
      assert result.failed_invitations == 0
      assert result.errors == []

      # Verify participants were created
      participants = Events.list_event_participants(event)
      assert length(participants) == 2

      # Check suggestion participant
      suggestion_participant = Enum.find(participants, &(&1.user_id == suggested_user.id))
      assert suggestion_participant.invited_by_user_id == organizer.id
      assert suggestion_participant.invitation_message == invitation_message
      assert suggestion_participant.metadata["invitation_method"] == "historical_suggestion"
      assert suggestion_participant.metadata["recommendation_level"] == "recommended"

      # Check email participant
      new_user = EventasaurusApp.Accounts.get_user_by_email("newuser@example.com")
      assert new_user != nil
      email_participant = Enum.find(participants, &(&1.user_id == new_user.id))
      assert email_participant.invited_by_user_id == organizer.id
      assert email_participant.metadata["invitation_method"] == "manual_email"
    end

    test "skips duplicate invitations for existing participants" do
      event = event_fixture()
      organizer = user_fixture()
      existing_user = user_fixture(%{email: "existing@example.com"})

      # Create existing participant
      {:ok, _} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: existing_user.id,
        role: :invitee,
        status: :pending
      })

      suggestion_structs = [%{user_id: existing_user.id}]

      result = Events.process_guest_invitations(event, organizer,
        suggestion_structs: suggestion_structs
      )

      assert result.successful_invitations == 0
      assert result.skipped_duplicates == 1
      assert result.failed_invitations == 0
    end

    test "handles mixed success, duplicates, and failures" do
      event = event_fixture()
      organizer = user_fixture()

      # User that exists
      existing_user = user_fixture(%{email: "existing@example.com"})

      # Create existing participant
      {:ok, _} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: existing_user.id,
        role: :invitee,
        status: :pending
      })

      # New user for suggestion
      new_user = user_fixture(%{email: "newuser@example.com"})

      suggestion_structs = [
        %{user_id: existing_user.id},  # Should be skipped (duplicate)
        %{user_id: new_user.id},       # Should succeed
        %{user_id: 99999}              # Should fail (user not found)
      ]

      manual_emails = ["fresh@example.com", "existing@example.com"]

      result = Events.process_guest_invitations(event, organizer,
        suggestion_structs: suggestion_structs,
        manual_emails: manual_emails
      )

      # 1 new suggestion + 1 fresh email = 2 successful
      # 1 existing suggestion + 1 existing email = 2 skipped
      # 1 invalid user = 1 failed
      assert result.successful_invitations == 2
      assert result.skipped_duplicates == 2
      assert result.failed_invitations == 1
      assert length(result.errors) == 1
    end
  end
end
