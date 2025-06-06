defmodule EventasaurusWeb.EventRegistrationCallbackTest do
  use EventasaurusWeb.ConnCase
  use Wallaby.Feature

  import Phoenix.LiveViewTest
  import Mox
  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Auth.{ClientMock, TestClient}
  alias EventasaurusApp.Events

  # Setup mocks and ETS table for TestClient
  setup :verify_on_exit!

  setup do
    # Set up the ETS table for TestClient
    TestClient.clear_test_users()

    :ok
  end

  describe "Event Registration with Email Confirmation Flow" do
    test "complete flow: register -> email -> callback -> registered", %{conn: conn} do
      # Setup event and mock user data
      event = event_fixture(%{slug: "test-event-123"})

      supabase_user = %{
        "id" => "supabase-user-123",
        "email" => "test@example.com",
        "user_metadata" => %{"name" => "Test User"}
      }

      # Mock the OTP request (email sent)
      expect_otp_request = fn email, metadata ->
        assert email == "test@example.com"
        assert metadata.name == "Test User"
        assert metadata.event_context.slug == "test-event-123"
        assert metadata.event_context.id == event.id
        {:ok, %{"email_sent" => true}}
      end

      # Mock the admin check (user doesn't exist initially)
      expect_admin_check = fn email ->
        assert email == "test@example.com"
        {:ok, nil}  # User doesn't exist
      end

      # Set up mocks for registration flow
      ClientMock
      |> expect(:admin_get_user_by_email, 1, expect_admin_check)
      |> expect(:sign_in_with_otp, 1, expect_otp_request)

      # Step 1: Initial registration attempt on event page
      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Fill and submit the registration form
      form_view = element(view, "#registration-form")
      render_change(form_view, %{"user" => %{"name" => "Test User", "email" => "test@example.com"}})
      render_submit(form_view, %{"user" => %{"name" => "Test User", "email" => "test@example.com"}})

      # Should show "Check Your Email" message
      assert has_element?(view, "[data-test='email-confirmation-ui']")
      assert has_text?(view, "Check Your Email")
      assert has_text?(view, "test@example.com")

      # Step 2: Simulate email confirmation callback with tokens
      # Set up the test user in ETS for the callback
      TestClient.set_test_user("valid-access-token", supabase_user)

      callback_params = %{
        "access_token" => "valid-access-token",
        "refresh_token" => "valid-refresh-token",
        "type" => "event_registration",
        "event_slug" => event.slug,
        "event_id" => to_string(event.id)
      }

      # Call the callback endpoint
      callback_conn = conn
                      |> get("/auth/callback", callback_params)

      # Should redirect to event page with success message
      assert redirected_to(callback_conn) == "/#{event.slug}"
      assert Phoenix.Flash.get(callback_conn.assigns.flash, :info) == "Welcome! You're now registered for this event."

      # Step 3: Verify user and participant were created
      # The user should now exist in our local database
      local_user = EventasaurusApp.Accounts.get_user_by_email("test@example.com")
      assert local_user != nil
      assert local_user.name == "Test User"
      assert local_user.supabase_id == "supabase-user-123"

      # The participant record should exist
      participant = Events.get_event_participant_by_event_and_user(event, local_user)
      assert participant != nil
      assert participant.role == :invitee
      assert participant.status == :pending
      assert participant.source == "email_confirmation_registration"
      assert participant.metadata["confirmed_via_email"] == true

      # Step 4: Verify subsequent visit shows registered state
      session_conn = callback_conn
                     |> Plug.Test.init_test_session(%{
                       access_token: "valid-access-token",
                       refresh_token: "valid-refresh-token"
                     })

      # Set up the test user for the authenticated session
      TestClient.set_test_user("valid-access-token", supabase_user)

      {:ok, final_view, _html} = live(session_conn, ~p"/#{event.slug}")

      # Should show registered state, not registration form
      refute has_element?(final_view, "#registration-form")
      assert has_text?(final_view, "You're registered!")
    end

    test "handles already registered user callback gracefully", %{conn: conn} do
      # Setup event and existing user/participant
      event = event_fixture(%{slug: "existing-event"})
      user = user_fixture(%{email: "existing@example.com", supabase_id: "existing-123"})

      # Create existing participant
      Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        source: "previous_registration"
      })

      supabase_user = %{
        "id" => "existing-123",
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

    test "handles callback errors gracefully", %{conn: conn} do
      event = event_fixture(%{slug: "error-event"})

      # Test authentication failure - don't set up any test user, so lookup will fail

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
  end
end
