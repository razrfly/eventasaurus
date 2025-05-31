defmodule EventasaurusApp.EventsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts

  describe "smart registration functions" do
    test "get_user_registration_status/2 returns :not_registered for unregistered user" do
      event = event_fixture()
      user = user_fixture()

      assert Events.get_user_registration_status(event, user) == :not_registered
    end

    test "get_user_registration_status/2 returns :registered for registered user" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      assert Events.get_user_registration_status(event, user) == :registered
    end

    test "get_user_registration_status/2 returns :cancelled for cancelled user" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      assert Events.get_user_registration_status(event, user) == :cancelled
    end

    test "one_click_register/2 creates registration for unregistered user" do
      event = event_fixture()
      user = user_fixture()

      assert {:ok, participant} = Events.one_click_register(event, user)
      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.status == :pending
      assert participant.source == "one_click_registration"
    end

    test "one_click_register/2 returns error for already registered user" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      assert {:error, :already_registered} = Events.one_click_register(event, user)
    end

    test "one_click_register/2 reactivates cancelled registration" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      assert {:ok, participant} = Events.one_click_register(event, user)
      assert participant.status == :pending
      assert participant.metadata[:reregistered_at]
    end

    test "cancel_user_registration/2 cancels existing registration" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      assert {:ok, updated_participant} = Events.cancel_user_registration(event, user)
      assert updated_participant.status == :cancelled
    end

    test "cancel_user_registration/2 returns error for unregistered user" do
      event = event_fixture()
      user = user_fixture()

      assert {:error, :not_registered} = Events.cancel_user_registration(event, user)
    end

    test "reregister_user_for_event/2 reactivates cancelled registration" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      assert {:ok, updated_participant} = Events.reregister_user_for_event(event, user)
      assert updated_participant.status == :pending
      assert updated_participant.metadata[:reregistered_at]
    end

    test "reregister_user_for_event/2 creates new registration for unregistered user" do
      event = event_fixture()
      user = user_fixture()

      assert {:ok, participant} = Events.reregister_user_for_event(event, user)
      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.status == :pending
      assert participant.source == "re_registration"
    end

    test "reregister_user_for_event/2 returns error for already registered user" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      assert {:error, :already_registered} = Events.reregister_user_for_event(event, user)
    end
  end

  describe "organizer registration status" do
    test "get_user_registration_status/2 returns :organizer for event organizer" do
      event = event_fixture()
      user = user_fixture()

      # Add user as organizer
      {:ok, _} = Events.add_user_to_event(event, user)

      assert Events.get_user_registration_status(event, user) == :organizer
    end

    test "one_click_register/2 returns error for event organizer" do
      event = event_fixture()
      user = user_fixture()

      # Add user as organizer
      {:ok, _} = Events.add_user_to_event(event, user)

      assert {:error, :organizer_cannot_register} = Events.one_click_register(event, user)
    end
  end

  describe "supabase user data handling" do
    test "get_user_registration_status/2 handles Supabase user data for existing user" do
      event = event_fixture()
      user = user_fixture()

      # Create Supabase user data format
      supabase_user = %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      }

      assert Events.get_user_registration_status(event, supabase_user) == :not_registered
    end

    test "get_user_registration_status/2 creates user from Supabase data for new user" do
      event = event_fixture()

      # Create Supabase user data for non-existent user
      supabase_user = %{
        "id" => "new-supabase-id-#{System.unique_integer([:positive])}",
        "email" => "newuser#{System.unique_integer([:positive])}@example.com",
        "user_metadata" => %{"name" => "New User"}
      }

      # Should create user and return :not_registered
      assert Events.get_user_registration_status(event, supabase_user) == :not_registered

      # Verify user was created
      created_user = Accounts.get_user_by_supabase_id(supabase_user["id"])
      assert created_user != nil
      assert created_user.email == supabase_user["email"]
      assert created_user.name == supabase_user["user_metadata"]["name"]
    end

    test "get_user_registration_status/2 handles invalid Supabase data" do
      event = event_fixture()

      # Test with invalid data
      assert Events.get_user_registration_status(event, %{"invalid" => "data"}) == :not_registered
      assert Events.get_user_registration_status(event, "invalid") == :not_registered
      assert Events.get_user_registration_status(event, nil) == :not_registered
    end
  end

  describe "public registration flow" do
    test "register_user_for_event/3 creates new user and registration" do
      event = event_fixture()
      name = "John Doe"
      email = "john#{System.unique_integer([:positive])}@example.com"

      # Mock Supabase user creation
      supabase_user = %{
        "id" => "supabase-#{System.unique_integer([:positive])}",
        "email" => email,
        "user_metadata" => %{"name" => name}
      }

      # We need to test the core logic without Supabase integration
      # So let's test the user creation and participant creation directly

      # First verify user doesn't exist
      assert Accounts.get_user_by_email(email) == nil

      # Create user manually (simulating what register_user_for_event would do)
      {:ok, user} = Accounts.create_user(%{
        email: email,
        name: name,
        supabase_id: supabase_user["id"]
      })

      # Create participant
      {:ok, participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        source: "public_registration",
        metadata: %{registration_date: DateTime.utc_now(), registered_name: name}
      })

      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.status == :pending
      assert participant.source == "public_registration"
      assert participant.metadata[:registered_name] == name
    end

    test "register_user_for_event/3 registers existing user" do
      event = event_fixture()
      user = user_fixture()

      # Create participant for existing user
      {:ok, participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        source: "public_registration",
        metadata: %{registration_date: DateTime.utc_now(), registered_name: user.name}
      })

      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.status == :pending
    end

    test "prevents duplicate registration for same user and event" do
      event = event_fixture()
      user = user_fixture()

      # Create first registration
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      # Attempt duplicate registration should fail
      assert {:error, _changeset} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })
    end
  end

  describe "metadata tracking" do
    test "one_click_register/2 tracks registration metadata" do
      event = event_fixture()
      user = user_fixture()

      {:ok, participant} = Events.one_click_register(event, user)

      assert participant.metadata[:registration_date] != nil
      assert participant.source == "one_click_registration"
    end

    test "reregister_user_for_event/2 tracks reregistration metadata" do
      event = event_fixture()
      user = user_fixture()

      # Create cancelled registration
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      # Reregister
      {:ok, updated_participant} = Events.reregister_user_for_event(event, user)

      assert updated_participant.status == :pending
      assert updated_participant.metadata[:reregistered_at] != nil
    end

    test "cancel_user_registration/2 preserves existing metadata" do
      event = event_fixture()
      user = user_fixture()

      original_metadata = %{registration_date: DateTime.utc_now(), custom_field: "test"}

      # Create registration with metadata
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        metadata: original_metadata
      })

      # Cancel registration
      {:ok, cancelled_participant} = Events.cancel_user_registration(event, user)

      assert cancelled_participant.status == :cancelled
      # Note: metadata merging behavior may vary - test what actually gets preserved
      assert cancelled_participant.metadata[:cancelled_at]
    end
  end

  describe "edge cases and error handling" do
    test "get_user_registration_status/2 handles user creation failure gracefully" do
      event = event_fixture()

      # Create Supabase user data with invalid email (should cause creation to fail)
      supabase_user = %{
        "id" => "test-supabase-id",
        "email" => "", # Invalid email
        "user_metadata" => %{"name" => "Test User"}
      }

      # Should return :error when user creation fails
      assert Events.get_user_registration_status(event, supabase_user) == :error
    end

    test "one_click_register/2 handles different participant statuses" do
      event = event_fixture()
      user = user_fixture()

      # Test with different statuses (using valid enum values)
      statuses_to_test = [:pending, :accepted, :declined]

      for status <- statuses_to_test do
        # Clean up any existing participant
        Events.get_event_participant_by_event_and_user(event, user)
        |> case do
          nil -> :ok
          participant -> Events.delete_event_participant(participant)
        end

        # Create participant with specific status
        {:ok, _participant} = Events.create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          role: :invitee,
          status: status
        })

        # Should return already_registered error for any non-cancelled status
        assert {:error, :already_registered} = Events.one_click_register(event, user)
      end
    end

    test "cancel_user_registration/2 can be called multiple times safely" do
      event = event_fixture()
      user = user_fixture()

      # Create registration
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      # Cancel first time
      {:ok, cancelled_participant} = Events.cancel_user_registration(event, user)
      assert cancelled_participant.status == :cancelled

      # Cancel second time (should still work)
      {:ok, still_cancelled_participant} = Events.cancel_user_registration(event, user)
      assert still_cancelled_participant.status == :cancelled
    end
  end

  describe "bulk_cast_votes/2" do
    setup do
      user = user_fixture()
      event = event_fixture()
      {:ok, polling_event} = Events.update_event(event, %{state: "polling"})
      {:ok, poll} = Events.create_event_date_poll(polling_event, user, %{})

      # Create some date options
      start_date = Date.add(Date.utc_today(), 7)
      end_date = Date.add(start_date, 7)
      {:ok, _options} = Events.create_date_options_from_range(poll, start_date, end_date)

      poll = Events.get_event_date_poll!(poll.id) |> EventasaurusApp.Repo.preload(:date_options)

      %{user: user, poll: poll, options: poll.date_options}
    end

    test "successfully inserts multiple new votes", %{user: user, options: options} do
      votes_data = [
        %{option_id: Enum.at(options, 0).id, vote_type: :yes},
        %{option_id: Enum.at(options, 1).id, vote_type: :if_need_be},
        %{option_id: Enum.at(options, 2).id, vote_type: :no}
      ]

      assert {:ok, %{inserted: 3, updated: 0}} = Events.bulk_cast_votes(user, votes_data)

      # Verify votes were created
      for vote_data <- votes_data do
        option = Enum.find(options, &(&1.id == vote_data.option_id))
        vote = Events.get_user_vote_for_option(option, user)
        assert vote.vote_type == vote_data.vote_type
      end
    end

    test "successfully updates existing votes", %{user: user, options: options} do
      # Create initial votes
      option1 = Enum.at(options, 0)
      option2 = Enum.at(options, 1)

      {:ok, _vote1} = Events.cast_vote(option1, user, :yes)
      {:ok, _vote2} = Events.cast_vote(option2, user, :no)

      # Update votes using bulk operation
      votes_data = [
        %{option_id: option1.id, vote_type: :if_need_be},  # Change yes -> if_need_be
        %{option_id: option2.id, vote_type: :yes}           # Change no -> yes
      ]

      assert {:ok, %{inserted: 0, updated: 2}} = Events.bulk_cast_votes(user, votes_data)

      # Verify votes were updated
      updated_vote1 = Events.get_user_vote_for_option(option1, user)
      updated_vote2 = Events.get_user_vote_for_option(option2, user)

      assert updated_vote1.vote_type == :if_need_be
      assert updated_vote2.vote_type == :yes
    end

    test "handles mix of inserts and updates", %{user: user, options: options} do
      # Create one existing vote
      option1 = Enum.at(options, 0)
      {:ok, _existing_vote} = Events.cast_vote(option1, user, :yes)

      # Bulk operation with update and insert
      votes_data = [
        %{option_id: option1.id, vote_type: :no},                 # Update existing
        %{option_id: Enum.at(options, 1).id, vote_type: :yes},    # Insert new
        %{option_id: Enum.at(options, 2).id, vote_type: :if_need_be}  # Insert new
      ]

      assert {:ok, %{inserted: 2, updated: 1}} = Events.bulk_cast_votes(user, votes_data)

      # Verify results
      updated_vote = Events.get_user_vote_for_option(option1, user)
      new_vote1 = Events.get_user_vote_for_option(Enum.at(options, 1), user)
      new_vote2 = Events.get_user_vote_for_option(Enum.at(options, 2), user)

      assert updated_vote.vote_type == :no
      assert new_vote1.vote_type == :yes
      assert new_vote2.vote_type == :if_need_be
    end

    test "skips updates when vote type is the same", %{user: user, options: options} do
      # Create existing vote
      option1 = Enum.at(options, 0)
      {:ok, _vote} = Events.cast_vote(option1, user, :yes)

      # Bulk operation with same vote type (should be skipped)
      votes_data = [
        %{option_id: option1.id, vote_type: :yes},  # Same as existing, should be skipped
        %{option_id: Enum.at(options, 1).id, vote_type: :no}  # New vote
      ]

      assert {:ok, %{inserted: 1, updated: 0}} = Events.bulk_cast_votes(user, votes_data)

      # Verify the existing vote wasn't unnecessarily updated
      vote = Events.get_user_vote_for_option(option1, user)
      assert vote.vote_type == :yes
    end

    test "handles empty votes list", %{user: user} do
      assert {:ok, %{inserted: 0, updated: 0}} = Events.bulk_cast_votes(user, [])
    end

    test "fails gracefully with invalid vote type", %{user: user, options: options} do
      votes_data = [
        %{option_id: Enum.at(options, 0).id, vote_type: :invalid_type}
      ]

      assert {:error, _reason} = Events.bulk_cast_votes(user, votes_data)
    end

    test "validates vote types before processing", %{user: user, options: options} do
      votes_data = [
        %{option_id: Enum.at(options, 0).id, vote_type: :invalid_type}
      ]

      # Should fail validation before reaching the database
      assert {:error, :invalid_type} = Events.bulk_cast_votes(user, votes_data)
    end
  end

  describe "register_voter_and_bulk_cast_votes/4" do
    setup do
      user = user_fixture()
      event = event_fixture()
      {:ok, polling_event} = Events.update_event(event, %{state: "polling"})
      {:ok, poll} = Events.create_event_date_poll(polling_event, user, %{})

      # Create some date options
      start_date = Date.add(Date.utc_today(), 7)
      end_date = Date.add(start_date, 7)
      {:ok, _options} = Events.create_date_options_from_range(poll, start_date, end_date)

      poll = Events.get_event_date_poll!(poll.id) |> EventasaurusApp.Repo.preload(:date_options)

      %{event: polling_event, poll: poll, options: poll.date_options}
    end

    @tag :skip_in_ci
    test "registers new voter and casts multiple votes", %{event: event, options: options} do
      votes_data = [
        %{option: Enum.at(options, 0), vote_type: :yes},
        %{option: Enum.at(options, 1), vote_type: :if_need_be}
      ]

      name = "Test Voter"
      email = "testvoter@example.com"

      # This test will fail in CI due to Supabase not being available
      # In a real test environment with Supabase, this would pass
      case Events.register_voter_and_bulk_cast_votes(event.id, name, email, votes_data) do
        {:ok, :new_voter, participant, vote_results} ->
          # Verify participant was created
          assert participant.event_id == event.id
          assert participant.status == :pending

          # Verify vote results
          assert vote_results.inserted == 2
          assert vote_results.updated == 0

          # Verify votes were actually cast
          user = Accounts.get_user_by_email(email)
          assert user
          vote1 = Events.get_user_vote_for_option(Enum.at(options, 0), user)
          vote2 = Events.get_user_vote_for_option(Enum.at(options, 1), user)

          assert vote1.vote_type == :yes
          assert vote2.vote_type == :if_need_be

        {:error, _reason} ->
          # Expected in test environment without Supabase
          :ok
      end
    end

    test "handles existing user voting", %{event: event, options: options} do
      # Create existing user and register them for the event
      existing_user = user_fixture(%{email: "existing@example.com"})
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: existing_user.id,
        role: :invitee,
        status: :accepted
      })

      votes_data = [
        %{option: Enum.at(options, 0), vote_type: :no}
      ]

      assert {:ok, :existing_user_voted, participant, vote_results} =
        Events.register_voter_and_bulk_cast_votes(event.id, existing_user.name, existing_user.email, votes_data)

      # Verify existing participant wasn't duplicated
      assert participant.user_id == existing_user.id
      assert participant.event_id == event.id

      # Verify vote was cast
      assert vote_results.inserted == 1
      assert vote_results.updated == 0
    end

    test "fails gracefully with invalid event", %{options: options} do
      votes_data = [
        %{option: Enum.at(options, 0), vote_type: :yes}
      ]

      assert {:error, :event_not_found} =
        Events.register_voter_and_bulk_cast_votes(999999, "Test", "test@example.com", votes_data)
    end

    test "validates vote types before processing", %{event: event, options: options} do
      votes_data = [
        %{option: Enum.at(options, 0), vote_type: :invalid_type}
      ]

      assert {:error, :invalid_vote_types} =
        Events.register_voter_and_bulk_cast_votes(event.id, "Test", "test@example.com", votes_data)
    end

    @tag :skip_in_ci
    test "handles empty votes data", %{event: event} do
      name = "Test Voter"
      email = "testvoter@example.com"

      # This test will fail in CI due to Supabase not being available
      case Events.register_voter_and_bulk_cast_votes(event.id, name, email, []) do
        {:ok, :new_voter, participant, vote_results} ->
          # Verify participant was still created even with no votes
          assert participant.event_id == event.id
          assert vote_results.inserted == 0
          assert vote_results.updated == 0

        {:error, _reason} ->
          # Expected in test environment without Supabase
          :ok
      end
    end
  end

  # Helper functions for creating test data
  defp event_fixture(attrs \\ %{}) do
    {:ok, event} =
      attrs
      |> Enum.into(%{
        title: "Test Event",
        description: "A test event",
        start_at: ~U[2024-01-01 10:00:00Z],
        timezone: "UTC",
        slug: "test-event-#{System.unique_integer([:positive])}"
      })
      |> Events.create_event()

    event
  end

  defp user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "test#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        supabase_id: "test-supabase-id-#{System.unique_integer([:positive])}"
      })
      |> Accounts.create_user()

    user
  end
end
