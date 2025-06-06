defmodule EventasaurusApp.Events.RegistrationFlowTest do
  @moduledoc """
  Integration tests for event registration flow including:
  - Regular event registration with existing users
  - Event registration with new users (OTP flow)
  - Voting registration flows
  - Error handling and edge cases
  """

  use EventasaurusApp.DataCase, async: true
  alias EventasaurusApp.{Events, Accounts, Repo}
  alias EventasaurusApp.Auth.ClientMock
  import Mox

  setup :verify_on_exit!

  describe "register_user_for_event/3 - Existing Users" do
    setup do
      event = insert(:event, title: "Test Conference", visibility: "public")

      # Create an existing user in Supabase (mocked response)
      supabase_user = %{
        "id" => "uuid-existing-user",
        "email" => "existing@example.com",
        "email_confirmed_at" => "2024-01-15T10:30:00.000Z",
        "user_metadata" => %{"name" => "Existing User"}
      }

      # Create corresponding local user
      user = insert(:user,
        email: "existing@example.com",
        supabase_id: "uuid-existing-user",
        name: "Existing User"
      )

      %{event: event, user: user, supabase_user: supabase_user}
    end

    test "successfully registers existing user for event", %{event: event, user: user, supabase_user: _supabase_user} do
      # No mocks needed - user exists locally so no API calls are made

      result = Events.register_user_for_event(event.id, "Existing User", "existing@example.com")

      assert {:ok, :existing_user_registered, participant} = result
      assert participant.user_id == user.id
      assert participant.event_id == event.id
      assert participant.metadata["registered_name"] == "Existing User"
    end

    test "prevents duplicate registration for existing user", %{event: event, user: user, supabase_user: _supabase_user} do
      # Create existing participant
      _existing_participant = insert(:event_participant, event: event, user: user)

      # No mocks needed - user exists locally so no API calls are made

      result = Events.register_user_for_event(event.id, "Existing User", "existing@example.com")

      assert {:error, :already_registered} = result
    end
  end

  describe "register_user_for_event/3 - New Users (OTP Flow)" do
    setup do
      event = insert(:event, title: "New User Event", visibility: "public")
      %{event: event}
    end

    test "successfully initiates registration for new user with OTP", %{event: event} do
      # Mock: OTP sent successfully
      ClientMock
      |> expect(:sign_in_with_otp, fn "newuser@example.com", event_context ->
        assert event_context.slug == event.slug
        assert event_context.id == event.id
        {:ok, %{
          "email_sent" => true,
          "email" => "newuser@example.com",
          "message_id" => "otp-12345"
        }}
      end)

      result = Events.register_user_for_event(event.id, "New User", "newuser@example.com")

      assert {:ok, :email_sent, response} = result
      assert response["email_sent"] == true
      assert response["email"] == "newuser@example.com"

      # Verify no participant was created yet (user must confirm email first)
      participants = Events.list_event_participants(event.id)
      assert Enum.empty?(participants)
    end

    test "handles OTP delivery failure", %{event: event} do
      # Mock: OTP sending fails
      ClientMock
      |> expect(:sign_in_with_otp, fn "newuser@example.com", _event_context ->
        {:error, %{status: 503, message: "Email service temporarily unavailable"}}
      end)

      result = Events.register_user_for_event(event.id, "New User", "newuser@example.com")

      assert {:error, %{status: 503, message: "Email service temporarily unavailable"}} = result
    end
  end

  describe "register_voter_and_cast_vote/5 - Voting Registration" do
    setup do
      event = insert(:event, state: "polling")
      poll = insert(:event_date_poll, event: event)
      option = insert(:event_date_option, event_date_poll: poll)

      %{event: event, poll: poll, option: option}
    end

    test "successfully registers new voter with OTP", %{event: event, poll: poll, option: option} do
      # Mock: OTP sent successfully
      ClientMock
      |> expect(:sign_in_with_otp, fn "voter@example.com", event_context ->
        assert event_context.slug == event.slug
        assert event_context.id == event.id
        {:ok, %{
          "email_sent" => true,
          "email" => "voter@example.com",
          "message_id" => "vote-otp-12345"
        }}
      end)

      result = Events.register_voter_and_cast_vote(event.id, "New Voter", "voter@example.com", option, :yes)

      assert {:ok, :email_sent, response} = result
      assert response["email_sent"] == true
      assert response["email"] == "voter@example.com"

      # Verify no vote was cast yet (user must confirm email first)
      votes = Events.list_votes_for_poll(poll)
      assert Enum.empty?(votes)
    end

    test "successfully registers existing voter and casts vote", %{event: event, poll: _poll, option: option} do
      # Create existing user
      user = insert(:user,
        email: "existing-voter@example.com",
        supabase_id: "uuid-existing-voter",
        name: "Existing Voter"
      )

      # No mocks needed - user exists locally

      result = Events.register_voter_and_cast_vote(event.id, "Existing Voter", "existing-voter@example.com", option, :yes)

      assert {:ok, :existing_user_voted, participant, vote} = result
      assert participant.user_id == user.id
      assert vote.event_date_option_id == option.id
      assert vote.user_id == user.id
    end
  end

  describe "register_voter_and_bulk_cast_votes/4 - Bulk Voting" do
    setup do
      event = insert(:event, state: "polling")
      poll = insert(:event_date_poll, event: event)
      option1 = insert(:event_date_option, event_date_poll: poll)
      option2 = insert(:event_date_option, event_date_poll: poll)

      vote_data = [
        %{option_id: option1.id, vote_type: :yes},
        %{option_id: option2.id, vote_type: :if_need_be}
      ]

      %{event: event, poll: poll, vote_data: vote_data}
    end

    test "successfully handles bulk voting with new user OTP", %{event: event, poll: poll, vote_data: vote_data} do
      # Mock: OTP sent successfully
      ClientMock
      |> expect(:sign_in_with_otp, fn "bulk-voter@example.com", event_context ->
        assert event_context.slug == event.slug
        assert event_context.id == event.id
        {:ok, %{
          "email_sent" => true,
          "email" => "bulk-voter@example.com",
          "message_id" => "bulk-vote-otp-12345"
        }}
      end)

      result = Events.register_voter_and_bulk_cast_votes(event.id, "Bulk Voter", "bulk-voter@example.com", vote_data)

      assert {:ok, :email_sent, response} = result
      assert response["email_sent"] == true
      assert response["email"] == "bulk-voter@example.com"

      # Verify no votes were cast yet
      votes = Events.list_votes_for_poll(poll)
      assert Enum.empty?(votes)
    end
  end

  describe "edge cases and error scenarios" do
    setup do
      event = insert(:event, title: "Edge Case Event")
      %{event: event}
    end

    test "handles OTP API failure during new user registration", %{event: event} do
      # Mock: OTP API fails
      ClientMock
      |> expect(:sign_in_with_otp, fn "user@example.com", _event_context ->
        {:error, %{status: 500, message: "Internal server error"}}
      end)

      result = Events.register_user_for_event(event.id, "Test User", "user@example.com")

      assert {:error, %{status: 500, message: "Internal server error"}} = result
    end

    test "handles missing event registration", %{} do
      non_existent_event_id = 99999

      result = Events.register_user_for_event(non_existent_event_id, "Test User", "user@example.com")

      assert {:error, _reason} = result
    end

    test "handles invalid email format", %{event: event} do
      result = Events.register_user_for_event(event.id, "Test User", "invalid-email")

      # Should fail at email validation before reaching Supabase
      assert {:error, _reason} = result
    end

    test "handles concurrent registration attempts", %{event: event} do
      # This test verifies that the database constraints prevent duplicate registrations
      # even if multiple requests arrive simultaneously

      _user = insert(:user, email: "concurrent@example.com")

      # Simulate two concurrent registration attempts
      task1 = Task.async(fn ->
        Events.register_user_for_event(event.id, "Concurrent User", "concurrent@example.com")
      end)

      task2 = Task.async(fn ->
        Events.register_user_for_event(event.id, "Concurrent User", "concurrent@example.com")
      end)

      results = [Task.await(task1), Task.await(task2)]

      # One should succeed, one should fail with already_registered
      success_count = Enum.count(results, fn
        {:ok, _, _} -> true
        _ -> false
      end)

      error_count = Enum.count(results, fn
        {:error, :already_registered} -> true
        _ -> false
      end)

      assert success_count == 1
      assert error_count == 1
    end
  end

  describe "data integrity and cleanup" do
    setup do
      event = insert(:event, title: "Data Integrity Event")
      %{event: event}
    end

    test "verifies participant data is correctly stored", %{event: event} do
      user = insert(:user, email: "integrity@example.com")

      # No mocks needed - user exists locally

      result = Events.register_user_for_event(event.id, user.name, user.email)

      assert {:ok, :existing_user_registered, participant} = result

      # Verify participant data integrity
      participant = Repo.preload(participant, [:user, :event])
      assert participant.user.id == user.id
      assert participant.event.id == event.id
      assert participant.metadata["registered_name"] == user.name
      assert participant.user.email == user.email
      assert participant.inserted_at != nil

      # Verify participant can be found in event participants list
      participants = Events.list_event_participants(event.id)
      assert length(participants) == 1
      assert hd(participants).id == participant.id
    end
  end
end
