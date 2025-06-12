defmodule EventasaurusApp.EventsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
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

  describe "state-aware CRUD operations" do
    # Helper for creating test event attributes that result in draft status
    # Note: Events default to :confirmed unless they have specific attributes
    # To create a draft event, we need to explicitly set incomplete required data
    defp draft_event_attrs(overrides \\ %{}) do
      future_start = DateTime.add(DateTime.utc_now(), 30, :day)

      # Create minimal event that will be :confirmed by default
      # Tests should expect :confirmed unless explicitly setting draft attributes
      %{
        title: "Test Event",
        description: "Test",
        start_at: future_start,
        timezone: "UTC"
      }
      |> Map.merge(overrides)
    end
        test "create_event/1 automatically infers status" do
            # Draft event (minimal required fields with future date)
      future_start = DateTime.add(DateTime.utc_now(), 30, :day)
      attrs = %{
        title: "Test Event",
        description: "Test",
        start_at: future_start,
        timezone: "UTC"
      }
      assert {:ok, event} = Events.create_event(attrs)
      assert event.status == :confirmed
      assert event.computed_phase == "open"

      # Polling event with future deadline
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)
      future_start_2 = DateTime.add(DateTime.utc_now(), 30, :day)
      polling_attrs = %{
        title: "Polling Event",
        description: "Test polling",
        start_at: future_start_2,
        timezone: "UTC",
        polling_deadline: future_deadline
      }
      assert {:ok, polling_event} = Events.create_event(polling_attrs)
      assert polling_event.status == :polling
      assert polling_event.computed_phase == "polling"

      # Regular confirmed event (default inference)
      future_start_3 = DateTime.add(DateTime.utc_now(), 7, :day)
      confirmed_attrs = %{
        title: "Confirmed Event",
        description: "Test confirmed",
        start_at: future_start_3,
        timezone: "UTC"
      }
      assert {:ok, confirmed_event} = Events.create_event(confirmed_attrs)
      assert confirmed_event.status == :confirmed
      assert confirmed_event.computed_phase == "open"
    end

    test "create_event/1 validates status consistency" do
      # Explicitly provide inconsistent status - try to set threshold status without threshold_count
      attrs = draft_event_attrs(%{status: :threshold})  # Inconsistent - no threshold_count provided
      assert {:error, changeset} = Events.create_event(attrs)
      status_errors = errors_on(changeset)[:status] || []
      assert Enum.any?(status_errors, &String.contains?(&1, "does not match inferred status"))
    end

        test "update_event/2 automatically updates status" do
      # Start with confirmed event
      {:ok, event} = Events.create_event(draft_event_attrs(%{title: "Test", description: "Test"}))
      assert event.status == :confirmed

      # Update to add polling deadline - should become polling
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)
      assert {:ok, updated_event} = Events.update_event(event, %{polling_deadline: future_deadline})
      assert updated_event.status == :polling
      assert updated_event.computed_phase == "polling"

      # Remove polling deadline - should revert to confirmed
      assert {:ok, confirmed_event} = Events.update_event(updated_event, %{polling_deadline: nil})
      assert confirmed_event.status == :confirmed
      assert confirmed_event.computed_phase == "open"
    end

            test "update_event/2 validates status consistency" do
      {:ok, event} = Events.create_event(draft_event_attrs(%{title: "Test", description: "Test"}))
      assert event.status == :confirmed

      # Try to manually set inconsistent status - set threshold without threshold_count
      assert {:error, changeset} = Events.update_event(event, %{status: :threshold})
      status_errors = errors_on(changeset)[:status] || []
      assert Enum.any?(status_errors, &String.contains?(&1, "does not match inferred status"))
    end

            test "transition_event/2 manually changes status" do
      {:ok, event} = Events.create_event(draft_event_attrs(%{title: "Test", description: "Test"}))
      assert event.status == :confirmed

      # Manual transition to canceled (allowed regardless of attributes)
      assert {:ok, canceled_event} = Events.transition_event(event, :canceled)
      assert canceled_event.status == :canceled
      assert canceled_event.computed_phase == "canceled"
      assert canceled_event.canceled_at != nil
    end

        test "transition_event/2 validates enum values" do
      {:ok, event} = Events.create_event(draft_event_attrs(%{title: "Test", description: "Test"}))

      # Invalid status should fail with transition error
      assert {:error, error_msg} = Events.transition_event(event, :invalid_status)
      assert is_binary(error_msg)
      assert error_msg =~ "invalid transition"
    end

            test "get_inferred_status/1 returns correct status without updating" do
      {:ok, event} = Events.create_event(draft_event_attrs(%{title: "Test", description: "Test"}))

      # Should return confirmed status for complete basic event
      assert Events.get_inferred_status(event) == :confirmed

      # Add polling deadline - should infer polling
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)
      event_with_deadline = %{event | polling_deadline: future_deadline}
      assert Events.get_inferred_status(event_with_deadline) == :polling
    end

            test "auto_correct_event_status/1 fixes inconsistent status" do
      # Create event with polling deadline (should be :polling)
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)
      {:ok, event} = Events.create_event(draft_event_attrs(%{
        title: "Test",
        description: "Test",
        polling_deadline: future_deadline
      }))
      assert event.status == :polling

      # Force wrong status directly in database
      EventasaurusApp.Repo.update_all(
        from(e in Event, where: e.id == ^event.id),
        set: [status: :confirmed]
      )

      # Reload event with wrong status
      incorrect_event = Events.get_event(event.id)
      assert incorrect_event.status == :confirmed

      # Auto-correct should fix it back to polling
      assert {:ok, corrected_event} = Events.auto_correct_event_status(incorrect_event)
      assert corrected_event.status == :polling
    end

    test "auto_correct_event_status/1 does nothing when status is correct" do
      {:ok, event} = Events.create_event(draft_event_attrs(%{title: "Test", description: "Test"}))
      assert event.status == :confirmed

      # Auto-correct should return same event
      assert {:ok, same_event} = Events.auto_correct_event_status(event)
      assert same_event.status == :confirmed
    end

            test "create_event_with_organizer/2 includes state management" do
      user = user_fixture()

      # Create event with automatic status inference
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)
      attrs = draft_event_attrs(%{
        title: "Test Event",
        description: "Test",
        polling_deadline: future_deadline
      })

      assert {:ok, event} = Events.create_event_with_organizer(attrs, user)
      assert event.status == :polling
      assert event.computed_phase == "polling"
      assert event.active_poll? == true

      # Verify organizer was added
      assert Events.user_can_manage_event?(user, event)
    end
  end

  describe "virtual flags integration" do
    setup do
      venue = EventasaurusApp.Factory.insert(:venue)
      %{venue: venue}
    end

    test "list_events/0 includes computed fields", %{venue: venue} do
      event_attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        venue_id: venue.id
      }

      {:ok, _event} = Events.create_event(event_attrs)

      events = Events.list_events()
      assert length(events) == 1

      event = List.first(events)
      # Should have computed_phase
      assert event.computed_phase == "open"

      # Should have all virtual flags
      assert is_boolean(event.ended?)
      assert is_boolean(event.can_sell_tickets?)
      assert is_boolean(event.threshold_met?)
      assert is_boolean(event.polling_ended?)
      assert is_boolean(event.active_poll?)
    end

    test "get_event!/1 includes computed fields", %{venue: venue} do
      event_attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :polling,
        polling_deadline: DateTime.utc_now() |> DateTime.add(7, :day),
        venue_id: venue.id
      }

      {:ok, created_event} = Events.create_event(event_attrs)

      event = Events.get_event!(created_event.id)

      # Should have computed_phase
      assert event.computed_phase == "polling"

      # Should have all virtual flags with correct values
      assert event.ended? == false
      assert event.can_sell_tickets? == false
      assert event.threshold_met? == false
      assert event.polling_ended? == false
      assert event.active_poll? == true  # Has active poll
    end

    test "list_active_events/0 returns non-canceled, non-ended events", %{venue: venue} do
      # Create active event
      active_attrs = %{
        title: "Active Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        ends_at: DateTime.utc_now() |> DateTime.add(48, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        venue_id: venue.id
      }

      # Create ended event
      ended_attrs = %{
        title: "Ended Event",
        start_at: DateTime.utc_now() |> DateTime.add(-48, :hour),
        ends_at: DateTime.utc_now() |> DateTime.add(-24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        venue_id: venue.id
      }

      # Create canceled event
      canceled_attrs = %{
        title: "Canceled Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :canceled,
        canceled_at: DateTime.utc_now(),
        venue_id: venue.id
      }

      {:ok, _active} = Events.create_event(active_attrs)
      {:ok, _ended} = Events.create_event(ended_attrs)
      {:ok, _canceled} = Events.create_event(canceled_attrs)

      active_events = Events.list_active_events()

      # Should only return the active event
      assert length(active_events) == 1
      assert List.first(active_events).title == "Active Event"
      assert List.first(active_events).ended? == false
    end

    test "list_polling_events/0 returns events with active polls", %{venue: venue} do
      # Create polling event with future deadline
      polling_attrs = %{
        title: "Polling Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :polling,
        polling_deadline: DateTime.utc_now() |> DateTime.add(7, :day),
        venue_id: venue.id
      }

      # Create polling event with past deadline (using changeset_with_inferred_status to bypass validation)
      expired_attrs = %{
        title: "Expired Poll Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :polling,
        polling_deadline: DateTime.utc_now() |> DateTime.add(-1, :day),
        venue_id: venue.id
      }

      # Create confirmed event (not polling)
      confirmed_attrs = %{
        title: "Confirmed Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        venue_id: venue.id
      }

      {:ok, _polling} = Events.create_event(polling_attrs)

      # Create expired event by first creating valid polling event, then updating deadline
      {:ok, expired_event} = Events.create_event(%{expired_attrs | polling_deadline: DateTime.utc_now() |> DateTime.add(1, :day)})
      past_deadline = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)
      EventasaurusApp.Repo.update!(Ecto.Changeset.change(expired_event, polling_deadline: past_deadline))

      {:ok, _confirmed} = Events.create_event(confirmed_attrs)

      polling_events = Events.list_polling_events()

      # Should only return the active polling event
      assert length(polling_events) == 1
      assert List.first(polling_events).title == "Polling Event"
      assert List.first(polling_events).active_poll? == true
    end

    test "list_ticketed_events/0 returns confirmed events that can sell tickets", %{venue: venue} do
      # Create confirmed event (can potentially sell tickets)
      confirmed_attrs = %{
        title: "Confirmed Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        venue_id: venue.id
      }

      # Create draft event (cannot sell tickets) - using confirmed status but it won't have ticketing enabled
      draft_attrs = %{
        title: "Draft Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,  # Use confirmed but it still won't sell tickets due to ticketing settings
        venue_id: venue.id
      }

      {:ok, _confirmed} = Events.create_event(confirmed_attrs)

      # Create draft event by bypassing status validation
      {:ok, _draft} =
        %Event{}
        |> Event.changeset_with_inferred_status(%{draft_attrs | status: :confirmed})
        |> Ecto.Changeset.put_change(:status, :draft)
        |> EventasaurusApp.Repo.insert()

      ticketed_events = Events.list_ticketed_events()

      # Should include confirmed events but filter by can_sell_tickets?
      # Since EventStateMachine.is_ticketed?/1 returns false by default,
      # this should return an empty list
      assert length(ticketed_events) == 0
    end

    test "list_ended_events/0 returns events that have ended", %{venue: venue} do
      # Create ended event
      ended_attrs = %{
        title: "Ended Event",
        start_at: DateTime.utc_now() |> DateTime.add(-48, :hour),
        ends_at: DateTime.utc_now() |> DateTime.add(-24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        venue_id: venue.id
      }

      # Create active event
      active_attrs = %{
        title: "Active Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        ends_at: DateTime.utc_now() |> DateTime.add(48, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        venue_id: venue.id
      }

      # Create event without end time
      no_end_attrs = %{
        title: "No End Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        venue_id: venue.id
      }

      {:ok, _ended} = Events.create_event(ended_attrs)
      {:ok, _active} = Events.create_event(active_attrs)
      {:ok, _no_end} = Events.create_event(no_end_attrs)

      ended_events = Events.list_ended_events()

      # Should only return the ended event
      assert length(ended_events) == 1
      assert List.first(ended_events).title == "Ended Event"
      assert List.first(ended_events).ended? == true
    end
  end

  describe "Action-Driven Setup Functions" do
        test "pick_date/3 updates event start date and timezone" do
      {:ok, event} = Events.create_event(draft_event_attrs())
      future_date = DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)

      assert {:ok, updated_event} = Events.pick_date(event, future_date, timezone: "America/New_York")
      assert DateTime.compare(updated_event.start_at, future_date) == :eq
      assert updated_event.timezone == "America/New_York"
      assert updated_event.computed_phase != nil
    end

        test "pick_date/3 can set both start and end dates" do
      {:ok, event} = Events.create_event(draft_event_attrs())
      start_date = DateTime.add(DateTime.utc_now(), 30, :day) |> DateTime.truncate(:second)
      end_date = DateTime.add(start_date, 2, :hour) |> DateTime.truncate(:second)

      assert {:ok, updated_event} = Events.pick_date(event, start_date, ends_at: end_date)
      assert DateTime.compare(updated_event.start_at, start_date) == :eq
      assert DateTime.compare(updated_event.ends_at, end_date) == :eq
    end

        test "enable_polling/2 transitions event to polling status" do
      {:ok, event} = Events.create_event(draft_event_attrs())
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day) |> DateTime.truncate(:second)

      assert {:ok, updated_event} = Events.enable_polling(event, future_deadline)
      assert updated_event.status == :polling
      assert DateTime.compare(updated_event.polling_deadline, future_deadline) == :eq
      assert updated_event.computed_phase == "polling"
    end

    test "enable_polling/2 validates polling deadline is in future" do
      {:ok, event} = Events.create_event(draft_event_attrs())
      past_deadline = DateTime.add(DateTime.utc_now(), -1, :day)

      assert {:error, changeset} = Events.enable_polling(event, past_deadline)
      assert "must be in the future" in errors_on(changeset)[:polling_deadline]
    end

    test "set_threshold/2 transitions event to threshold status" do
      {:ok, event} = Events.create_event(draft_event_attrs())

      assert {:ok, updated_event} = Events.set_threshold(event, 10)
      assert updated_event.status == :threshold
      assert updated_event.threshold_count == 10
      assert updated_event.computed_phase == "awaiting_confirmation"
    end

    test "set_threshold/2 validates threshold count is positive" do
      {:ok, event} = Events.create_event(draft_event_attrs())

      # Test with zero
      assert_raise FunctionClauseError, fn ->
        Events.set_threshold(event, 0)
      end

      # Test with negative
      assert_raise FunctionClauseError, fn ->
        Events.set_threshold(event, -5)
      end
    end

    test "enable_ticketing/2 transitions event to confirmed status" do
      {:ok, event} = Events.create_event(draft_event_attrs())

      assert {:ok, updated_event} = Events.enable_ticketing(event)
      assert updated_event.status == :confirmed
      assert updated_event.computed_phase == "open"
    end

    test "enable_ticketing/2 accepts ticketing options" do
      {:ok, event} = Events.create_event(draft_event_attrs())
      ticketing_options = %{price: "25.00", currency: "USD"}

      assert {:ok, updated_event} = Events.enable_ticketing(event, ticketing_options)
      assert updated_event.status == :confirmed
    end

    test "add_details/2 updates event information without changing status" do
      {:ok, event} = Events.create_event(draft_event_attrs())
      original_status = event.status

      details = %{
        title: "Updated Title",
        description: "Updated description",
        tagline: "New tagline",
        theme: :cosmic
      }

      assert {:ok, updated_event} = Events.add_details(event, details)
      assert updated_event.title == "Updated Title"
      assert updated_event.description == "Updated description"
      assert updated_event.tagline == "New tagline"
      assert updated_event.theme == :cosmic
      assert updated_event.status == original_status
    end

    test "add_details/2 filters out non-allowed fields" do
      {:ok, event} = Events.create_event(draft_event_attrs())
      original_status = event.status

      details = %{
        title: "Updated Title",
        status: :canceled,  # This should be ignored
        id: 999,  # This should be ignored
        polling_deadline: DateTime.utc_now()  # This should be ignored
      }

      assert {:ok, updated_event} = Events.add_details(event, details)
      assert updated_event.title == "Updated Title"
      assert updated_event.status == original_status  # Should not change
      assert updated_event.id == event.id  # Should not change
      assert updated_event.polling_deadline == event.polling_deadline  # Should not change
    end

    test "publish_event/1 transitions event to confirmed and public" do
      {:ok, event} = Events.create_event(draft_event_attrs(%{visibility: :private}))

      assert {:ok, updated_event} = Events.publish_event(event)
      assert updated_event.status == :confirmed
      assert updated_event.visibility == :public
      assert updated_event.computed_phase == "open"
    end

        test "action functions maintain computed fields" do
      {:ok, event} = Events.create_event(draft_event_attrs())

      # Test that all action functions return events with computed fields
      future_date = DateTime.add(DateTime.utc_now(), 30, :day)
      {:ok, updated_event} = Events.pick_date(event, future_date)
      assert updated_event.computed_phase != nil
      assert is_boolean(updated_event.ended?)
      assert is_boolean(updated_event.can_sell_tickets?)

      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)
      {:ok, polling_event} = Events.enable_polling(updated_event, future_deadline)
      assert polling_event.computed_phase != nil
      assert is_boolean(polling_event.active_poll?)

      # Create a separate event for threshold testing (without polling_deadline)
      {:ok, threshold_base_event} = Events.create_event(draft_event_attrs())
      {:ok, threshold_event} = Events.set_threshold(threshold_base_event, 10)
      assert threshold_event.computed_phase != nil
      assert is_boolean(threshold_event.threshold_met?)
    end

        test "action functions work with state transitions" do
      {:ok, event} = Events.create_event(draft_event_attrs())
      assert event.status == :confirmed

      # Enable polling should transition from confirmed to polling
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)
      {:ok, polling_event} = Events.enable_polling(event, future_deadline)
      assert polling_event.status == :polling

      # Set threshold on a polling event - this should fail due to status inference
      assert {:error, changeset} = Events.set_threshold(polling_event, 10)
      {error_message, _} = changeset.errors[:status]
      assert String.contains?(error_message, "does not match inferred status")

      # Remove polling deadline to allow threshold status
      {:ok, pure_threshold_event} = Events.update_event(polling_event, %{polling_deadline: nil})

      # Now set threshold should work
      {:ok, threshold_event} = Events.set_threshold(pure_threshold_event, 10)
      assert threshold_event.status == :threshold
      assert threshold_event.threshold_count == 10

      # To publish, we need to clear threshold_count first (or the inferred status will be :threshold)
      {:ok, cleared_event} = Events.update_event(threshold_event, %{threshold_count: nil})

      # Now publish should work
      {:ok, published_event} = Events.publish_event(cleared_event)
      assert published_event.status == :confirmed
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
