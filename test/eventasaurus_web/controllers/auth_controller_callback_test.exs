defmodule EventasaurusWeb.Auth.AuthControllerCallbackTest do
  use EventasaurusWeb.ConnCase

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Auth.TestClient
  alias EventasaurusApp.Events

  # Setup test data
  setup do
    TestClient.clear_test_users()
    :ok
  end

  describe "auth callback for event registration" do
    test "successfully completes event registration after email confirmation", %{conn: conn} do
      # Setup event and mock user data
      event = event_fixture(%{slug: "test-event-callback"})

            supabase_user = %{
        "id" => "callback-user-123",
        "email" => "callback@example.com",
        "user_metadata" => %{"name" => "Callback User"}
      }

      # Set up test user for authentication
      TestClient.set_test_user("valid-access-token", supabase_user)

      # Simulate email confirmation callback with event context
      callback_params = %{
        "access_token" => "valid-access-token",
        "refresh_token" => "valid-refresh-token",
        "type" => "event_registration",
        "event_slug" => event.slug,
        "event_id" => to_string(event.id)
      }

      # Call the callback endpoint
      callback_conn = conn |> get("/auth/callback", callback_params)

      # Should redirect to event page with success message
      assert redirected_to(callback_conn) == "/#{event.slug}"
      assert Phoenix.Flash.get(callback_conn.assigns.flash, :info) == "Welcome! You're now registered for this event."

      # Verify user was created in local database
      local_user = EventasaurusApp.Accounts.get_user_by_email("callback@example.com")
      assert local_user != nil
      assert local_user.name == "Callback User"
      assert local_user.supabase_id == "callback-user-123"

      # Verify participant record was created
      participant = Events.get_event_participant_by_event_and_user(event, local_user)
      assert participant != nil
      assert participant.role == :invitee
      assert participant.status == :pending
      assert participant.source == "email_confirmation_registration"
      assert participant.metadata["confirmed_via_email"] == true
    end

    test "handles already registered user gracefully", %{conn: conn} do
      # Setup event and existing user/participant
      event = event_fixture(%{slug: "existing-user-event"})
      user = user_fixture(%{email: "existing@example.com", supabase_id: "existing-user-123"})

      # Create existing participant
      Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        source: "previous_registration"
      })

      supabase_user = %{
        "id" => "existing-user-123",
        "email" => "existing@example.com",
        "user_metadata" => %{"name" => user.name}
      }

      # Set up test user for authentication
      TestClient.set_test_user("valid-access-token", supabase_user)

      # Simulate callback for already registered user
      callback_params = %{
        "access_token" => "valid-access-token",
        "type" => "event_registration",
        "event_slug" => event.slug,
        "event_id" => to_string(event.id)
      }

      callback_conn = conn |> get("/auth/callback", callback_params)

      # Should redirect with "already registered" message
      assert redirected_to(callback_conn) == "/#{event.slug}"
      assert Phoenix.Flash.get(callback_conn.assigns.flash, :info) == "Welcome back! You're already registered for this event."
    end

    test "handles authentication failure gracefully", %{conn: conn} do
      event = event_fixture(%{slug: "error-event"})

      # Don't set up any test user - this will cause authentication failure

      callback_params = %{
        "access_token" => "invalid-token",
        "type" => "event_registration",
        "event_slug" => event.slug,
        "event_id" => to_string(event.id)
      }

      callback_conn = conn |> get("/auth/callback", callback_params)

      assert redirected_to(callback_conn) == "/#{event.slug}"
      assert Phoenix.Flash.get(callback_conn.assigns.flash, :error) == "Authentication failed. Please try again."
    end

    test "handles regular authentication callback without event context", %{conn: conn} do
      supabase_user = %{
        "id" => "regular-user-123",
        "email" => "regular@example.com",
        "user_metadata" => %{"name" => "Regular User"}
      }

      # Set up test user for authentication
      TestClient.set_test_user("valid-access-token", supabase_user)

      # Regular callback without event context
      callback_params = %{
        "access_token" => "valid-access-token",
        "refresh_token" => "valid-refresh-token"
      }

      callback_conn = conn |> get("/auth/callback", callback_params)

      # Should redirect to dashboard
      assert redirected_to(callback_conn) == "/dashboard"
      assert Phoenix.Flash.get(callback_conn.assigns.flash, :info) == "Successfully signed in!"
    end
  end
end
