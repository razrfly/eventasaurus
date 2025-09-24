defmodule EventasaurusApp.EventsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  describe "events" do
    test "list_events/0 returns all events" do
      event = event_fixture()
      events = Events.list_events()
      assert length(events) == 1

      returned_event = List.first(events)
      assert returned_event.id == event.id
      assert returned_event.title == event.title
      assert returned_event.taxation_type == "ticketless"
    end

    test "get_event!/1 returns the event with given id" do
      event = event_fixture()
      returned_event = Events.get_event!(event.id)

      assert returned_event.id == event.id
      assert returned_event.title == event.title
      assert returned_event.taxation_type == "ticketless"
      # get_event! should preload users
      assert is_list(returned_event.users)
    end

    test "create_event/1 with valid data creates a event" do
      valid_attrs = %{
        title: "Some title",
        description: "Some description",
        start_at: ~N[2024-05-21 14:20:00],
        timezone: "UTC"
      }

      assert {:ok, %Event{} = event} = Events.create_event(valid_attrs)
      assert event.title == "Some title"
      assert event.description == "Some description"
      assert event.start_at == ~U[2024-05-21 14:20:00Z]
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

      result =
        Events.process_guest_invitations(event, organizer,
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
      {:ok, _} =
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: existing_user.id,
          role: :invitee,
          status: :pending
        })

      suggestion_structs = [%{user_id: existing_user.id}]

      result =
        Events.process_guest_invitations(event, organizer, suggestion_structs: suggestion_structs)

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
      {:ok, _} =
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: existing_user.id,
          role: :invitee,
          status: :pending
        })

      # New user for suggestion
      new_user = user_fixture(%{email: "newuser@example.com"})

      suggestion_structs = [
        # Should be skipped (duplicate)
        %{user_id: existing_user.id},
        # Should succeed
        %{user_id: new_user.id},
        # Should fail (user not found)
        %{user_id: 99999}
      ]

      manual_emails = ["fresh@example.com", "existing@example.com"]

      result =
        Events.process_guest_invitations(event, organizer,
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

    test "direct add mode creates participants with confirmed status" do
      event = event_fixture()
      organizer = user_fixture()

      # Create a user for suggestion
      suggested_user = user_fixture(%{email: "direct@example.com", name: "Direct User"})

      suggestion_structs = [
        %{
          user_id: suggested_user.id,
          recommendation_level: "recommended",
          total_score: 9.0
        }
      ]

      manual_emails = ["directnew@example.com"]

      result =
        Events.process_guest_invitations(event, organizer,
          suggestion_structs: suggestion_structs,
          manual_emails: manual_emails,
          invitation_message: "This should be ignored",
          mode: :direct_add
        )

      # Should have 2 successful direct adds
      assert result.successful_invitations == 2
      assert result.skipped_duplicates == 0
      assert result.failed_invitations == 0
      assert result.errors == []

      # Verify participants were created with accepted status
      participants = Events.list_event_participants(event)
      assert length(participants) == 2

      # All participants should be accepted (not pending)
      Enum.each(participants, fn participant ->
        assert participant.status == :accepted
        assert participant.invited_by_user_id == organizer.id
        assert participant.invited_at != nil
        # For direct add, invitation_message should be nil
        assert participant.invitation_message == nil
      end)

      # Check suggestion participant metadata
      suggestion_participant = Enum.find(participants, &(&1.user_id == suggested_user.id))
      assert suggestion_participant.metadata["invitation_method"] == "direct_add_suggestion"
      assert suggestion_participant.metadata["recommendation_level"] == "recommended"

      # Check email participant metadata
      new_user = EventasaurusApp.Accounts.get_user_by_email("directnew@example.com")
      email_participant = Enum.find(participants, &(&1.user_id == new_user.id))
      assert email_participant.metadata["invitation_method"] == "direct_add_email"
      assert email_participant.metadata["email_provided"] == "directnew@example.com"
    end
  end

  describe "threshold functionality" do
    test "threshold_met?/1 returns false for attendee_count threshold when not met" do
      event =
        event_fixture(%{
          threshold_type: "attendee_count",
          threshold_count: 5
        })

      # By default, there are no participants, so threshold should not be met
      assert Event.threshold_met?(event) == false
    end

    test "threshold_met?/1 returns false for revenue threshold when not met" do
      event =
        event_fixture(%{
          threshold_type: "revenue",
          threshold_revenue_cents: 10000
        })

      # By default, there are no orders, so threshold should not be met
      assert Event.threshold_met?(event) == false
    end

    test "threshold query functions exist and return results" do
      # Test that our new query functions exist and return empty lists by default
      assert Events.list_threshold_events() == []
      assert Events.list_events_by_threshold_type("attendee_count") == []
      assert Events.list_threshold_met_events() == []
      assert Events.list_threshold_pending_events() == []
      assert Events.list_events_by_min_revenue(1000) == []
      assert Events.list_events_by_min_attendee_count(5) == []
    end
  end

  describe "taxation_type validation" do
    @describetag :taxation_type
    test "create_event/1 with valid taxation_type 'ticketed_event' succeeds" do
      valid_attrs = %{
        title: "Paid Concert",
        description: "A ticketed music event",
        start_at: ~N[2024-12-01 20:00:00],
        timezone: "UTC",
        taxation_type: "ticketed_event",
        is_ticketed: true
      }

      assert {:ok, %Event{} = event} = Events.create_event(valid_attrs)
      assert event.taxation_type == "ticketed_event"
      assert event.is_ticketed == true
    end

    test "create_event/1 with valid taxation_type 'contribution_collection' succeeds" do
      valid_attrs = %{
        title: "Charity Fundraiser",
        description: "A non-profit fundraising event",
        start_at: ~N[2024-12-01 18:00:00],
        timezone: "UTC",
        taxation_type: "contribution_collection",
        is_ticketed: false
      }

      assert {:ok, %Event{} = event} = Events.create_event(valid_attrs)
      assert event.taxation_type == "contribution_collection"
      assert event.is_ticketed == false
    end

    test "create_event/1 with valid taxation_type 'ticketless' succeeds" do
      valid_attrs = %{
        title: "Free Community Event",
        description: "A ticketless community gathering",
        start_at: ~N[2024-12-01 16:00:00],
        timezone: "UTC",
        taxation_type: "ticketless",
        is_ticketed: false
      }

      assert {:ok, %Event{} = event} = Events.create_event(valid_attrs)
      assert event.taxation_type == "ticketless"
      assert event.is_ticketed == false
    end

    test "create_event/1 defaults taxation_type to 'ticketless' when not provided" do
      valid_attrs = %{
        title: "Default Event",
        description: "An event with default taxation",
        start_at: ~N[2024-12-01 15:00:00],
        timezone: "UTC"
      }

      assert {:ok, %Event{} = event} = Events.create_event(valid_attrs)
      assert event.taxation_type == "ticketless"
    end

    test "create_event/1 with invalid taxation_type returns error changeset" do
      invalid_attrs = %{
        title: "Invalid Event",
        description: "An event with invalid taxation type",
        start_at: ~N[2024-12-01 15:00:00],
        timezone: "UTC",
        taxation_type: "invalid_type"
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Events.create_event(invalid_attrs)

      assert "must be one of: ticketed_event, contribution_collection, ticketless" in errors_on(
               changeset
             ).taxation_type
    end

    test "Event.changeset/2 validates taxation_type against valid values" do
      # Test valid values
      changeset1 = Event.changeset(%Event{}, %{taxation_type: "ticketed_event"})
      refute changeset1.errors[:taxation_type]

      changeset2 = Event.changeset(%Event{}, %{taxation_type: "contribution_collection"})
      refute changeset2.errors[:taxation_type]

      changeset3 = Event.changeset(%Event{}, %{taxation_type: "ticketless"})
      refute changeset3.errors[:taxation_type]

      # Test invalid value
      changeset4 = Event.changeset(%Event{}, %{taxation_type: "invalid_type"})
      assert changeset4.errors[:taxation_type]
    end

    test "Event.changeset/2 enforces business rule: contribution_collection events cannot be ticketed" do
      # Valid combination: contribution_collection + is_ticketed=false
      changeset1 =
        Event.changeset(%Event{}, %{
          taxation_type: "contribution_collection",
          is_ticketed: false
        })

      refute changeset1.errors[:is_ticketed]

      # Invalid combination: contribution_collection + is_ticketed=true
      changeset2 =
        Event.changeset(%Event{}, %{
          taxation_type: "contribution_collection",
          is_ticketed: true
        })

      assert changeset2.errors[:is_ticketed]

      assert "must be false for contribution collection events" in errors_on(changeset2).is_ticketed
    end

    test "Event.changeset/2 enforces business rule: ticketless events cannot be ticketed" do
      # Valid combination: ticketless + is_ticketed=false
      changeset1 =
        Event.changeset(%Event{}, %{
          taxation_type: "ticketless",
          is_ticketed: false
        })

      refute changeset1.errors[:is_ticketed]

      # Invalid combination: ticketless + is_ticketed=true
      changeset2 =
        Event.changeset(%Event{}, %{
          taxation_type: "ticketless",
          is_ticketed: true
        })

      assert changeset2.errors[:is_ticketed]
      assert "must be false for ticketless events" in errors_on(changeset2).is_ticketed
    end

    test "Event.changeset/2 allows all combinations for ticketed_event taxation type" do
      # Both combinations should be valid for ticketed_event
      changeset1 =
        Event.changeset(%Event{}, %{
          taxation_type: "ticketed_event",
          is_ticketed: true
        })

      refute changeset1.errors[:taxation_type]

      changeset2 =
        Event.changeset(%Event{}, %{
          taxation_type: "ticketed_event",
          # Free events can still be taxed as ticketed events
          is_ticketed: false
        })

      refute changeset2.errors[:taxation_type]
    end

    test "update_event/2 can change taxation_type while respecting business rules" do
      # Create event as ticketed_event
      event =
        event_fixture(%{
          taxation_type: "ticketed_event",
          is_ticketed: true
        })

      # Can update to contribution_collection if is_ticketed is also updated to false
      update_attrs = %{
        taxation_type: "contribution_collection",
        is_ticketed: false
      }

      assert {:ok, %Event{} = updated_event} = Events.update_event(event, update_attrs)
      assert updated_event.taxation_type == "contribution_collection"
      assert updated_event.is_ticketed == false
    end

    test "update_event/2 fails when trying to set invalid taxation_type combination" do
      event =
        event_fixture(%{
          taxation_type: "ticketed_event",
          is_ticketed: false
        })

      # Try to set contribution_collection but leave is_ticketed as true
      invalid_attrs = %{
        taxation_type: "contribution_collection",
        is_ticketed: true
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Events.update_event(event, invalid_attrs)

      assert "must be false for contribution collection events" in errors_on(changeset).is_ticketed
    end

    test "Event.valid_taxation_types/0 returns all valid taxation types" do
      valid_types = Event.valid_taxation_types()
      assert "ticketed_event" in valid_types
      assert "contribution_collection" in valid_types
      assert "ticketless" in valid_types
      assert length(valid_types) == 3
    end
  end
end
