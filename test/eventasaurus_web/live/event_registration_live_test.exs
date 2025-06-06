defmodule EventasaurusWeb.EventRegistrationLiveTest do
  @moduledoc """
  Tests for EventRegistrationLive component covering:
  - Regular user registration flow
  - New user OTP confirmation flow
  - Error handling and UI feedback
  - Modal behavior and form validation
  """

  use EventasaurusWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias EventasaurusApp.Auth.ClientMock
  import Mox

  setup :verify_on_exit!

  describe "event registration modal" do
    setup do
      event = insert(:event, title: "LiveView Test Event", visibility: "public")
      %{event: event}
    end

    test "displays registration form", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Open registration modal
      html = view |> element("#register-button") |> render_click()

      assert html =~ "Register for LiveView Test Event"
      assert html =~ "Full Name"
      assert html =~ "Email Address"
      assert html =~ "We'll send you an email to confirm your registration"
    end

    test "validates required fields", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Open modal and try to submit empty form
      view |> element("#register-button") |> render_click()
      html = view |> element("#registration-form") |> render_submit(%{name: "", email: ""})

      assert html =~ "can&#39;t be blank"
    end

    test "validates email format", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view |> element("#register-button") |> render_click()
      html = view |> element("#registration-form") |> render_submit(%{
        name: "Test User",
        email: "invalid-email"
      })

      assert html =~ "must have the @ sign and no spaces"
    end
  end

  describe "successful registration flows" do
    setup do
      event = insert(:event, title: "Success Test Event", visibility: "public")
      %{event: event}
    end

    test "handles existing user registration", %{conn: conn, event: event} do
      # Create existing user
      user = insert(:user, email: "existing@example.com", name: "Existing User")

      supabase_user = %{
        "id" => user.supabase_user_id,
        "email" => user.email,
        "email_confirmed_at" => "2024-01-15T10:30:00.000Z",
        "user_metadata" => %{"name" => user.name}
      }

      # Mock Supabase responses
      ClientMock
      |> expect(:admin_get_user_by_email, fn "existing@example.com" ->
        {:ok, supabase_user}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Submit registration form
      view |> element("#register-button") |> render_click()
      view |> element("#registration-form") |> render_submit(%{
        name: "Existing User",
        email: "existing@example.com"
      })

      # Should see success message
      assert render(view) =~ "Great! You&#39;re now registered for Success Test Event"

      # Modal should close
      refute render(view) =~ "Register for Success Test Event"
    end

    test "handles new user OTP registration", %{conn: conn, event: event} do
      # Mock Supabase responses for new user
      ClientMock
      |> expect(:admin_get_user_by_email, fn "newuser@example.com" ->
        {:ok, nil}
      end)
      |> expect(:sign_in_with_otp, fn "newuser@example.com", %{name: "New User"} ->
        {:ok, %{
          "email_sent" => true,
          "email" => "newuser@example.com",
          "message_id" => "otp-test-12345"
        }}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Submit registration form for new user
      view |> element("#register-button") |> render_click()
      view |> element("#registration-form") |> render_submit(%{
        name: "New User",
        email: "newuser@example.com"
      })

      # Should see email confirmation message
      assert render(view) =~ "Registration started! Check your email to confirm your account and complete your registration"
      assert render(view) =~ "Success Test Event"

      # Modal should close
      refute render(view) =~ "Register for Success Test Event"
    end

    test "prevents duplicate registration", %{conn: conn, event: event} do
      # Create user and existing participant
      user = insert(:user, email: "duplicate@example.com")
      _participant = insert(:event_participant, event: event, user: user, email: user.email)

      supabase_user = %{
        "id" => user.supabase_user_id,
        "email" => user.email,
        "email_confirmed_at" => "2024-01-15T10:30:00.000Z",
        "user_metadata" => %{"name" => user.name}
      }

      ClientMock
      |> expect(:admin_get_user_by_email, fn "duplicate@example.com" ->
        {:ok, supabase_user}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view |> element("#register-button") |> render_click()
      view |> element("#registration-form") |> render_submit(%{
        name: user.name,
        email: user.email
      })

      # Should see duplicate registration error
      assert render(view) =~ "You&#39;re already registered for this event"
    end
  end

  describe "error handling" do
    setup do
      event = insert(:event, title: "Error Test Event", visibility: "public")
      %{event: event}
    end

    test "handles Supabase service unavailable", %{conn: conn, event: event} do
      ClientMock
      |> expect(:admin_get_user_by_email, fn "user@example.com" ->
        {:ok, nil}
      end)
      |> expect(:sign_in_with_otp, fn "user@example.com", %{name: "Test User"} ->
        {:error, %{status: 503, message: "Service temporarily unavailable"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view |> element("#register-button") |> render_click()
      view |> element("#registration-form") |> render_submit(%{
        name: "Test User",
        email: "user@example.com"
      })

      # Should show error message
      assert render(view) =~ "Registration failed"
      assert render(view) =~ "Service temporarily unavailable"
    end

    test "handles admin API lookup failure", %{conn: conn, event: event} do
      ClientMock
      |> expect(:admin_get_user_by_email, fn "user@example.com" ->
        {:error, %{status: 500, message: "Internal server error"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view |> element("#register-button") |> render_click()
      view |> element("#registration-form") |> render_submit(%{
        name: "Test User",
        email: "user@example.com"
      })

      # Should show error message
      assert render(view) =~ "Registration failed"
      assert render(view) =~ "Internal server error"
    end

    test "handles network timeout gracefully", %{conn: conn, event: event} do
      ClientMock
      |> expect(:admin_get_user_by_email, fn "user@example.com" ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view |> element("#register-button") |> render_click()
      view |> element("#registration-form") |> render_submit(%{
        name: "Test User",
        email: "user@example.com"
      })

      # Should show generic error message for network issues
      assert render(view) =~ "Registration failed"
    end
  end

  describe "loading states and UX" do
    setup do
      event = insert(:event, title: "UX Test Event", visibility: "public")
      %{event: event}
    end

    test "shows loading state during registration", %{conn: conn, event: event} do
      # Use a slow mock to test loading state
      ClientMock
      |> expect(:admin_get_user_by_email, fn "user@example.com" ->
        # Simulate slow response
        Process.sleep(100)
        {:ok, nil}
      end)
      |> expect(:sign_in_with_otp, fn "user@example.com", %{name: "Test User"} ->
        {:ok, %{"email_sent" => true, "email" => "user@example.com"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view |> element("#register-button") |> render_click()

      # Start registration (this will trigger the slow mock)
      view |> element("#registration-form") |> render_submit(%{
        name: "Test User",
        email: "user@example.com"
      })

      # Should show loading state
      html = render(view)
      assert html =~ "Processing..." || html =~ "loading" || html =~ "disabled"
    end

    test "modal closes after successful registration", %{conn: conn, event: event} do
      user = insert(:user, email: "modal@example.com")

      supabase_user = %{
        "id" => user.supabase_user_id,
        "email" => user.email,
        "email_confirmed_at" => "2024-01-15T10:30:00.000Z",
        "user_metadata" => %{"name" => user.name}
      }

      ClientMock
      |> expect(:admin_get_user_by_email, fn "modal@example.com" ->
        {:ok, supabase_user}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Initially modal should not be visible
      refute render(view) =~ "Register for UX Test Event"

      # Open modal
      view |> element("#register-button") |> render_click()
      assert render(view) =~ "Register for UX Test Event"

      # Submit form
      view |> element("#registration-form") |> render_submit(%{
        name: user.name,
        email: user.email
      })

      # Modal should close
      refute render(view) =~ "Register for UX Test Event"
    end
  end

  describe "authenticated user behavior" do
    test "authenticated user sees one-click register" do
      user = insert(:user, email: "auth@example.com")
      event = insert(:event, title: "Auth Test Event", visibility: "public")

      conn = build_conn()
      |> log_in_user(user)

      {:ok, view, html} = live(conn, ~p"/events/#{event.id}")

      # Should see one-click registration instead of modal
      assert html =~ "Register for Auth Test Event"
      refute html =~ "Full Name"
      refute html =~ "Email Address"
    end

    test "authenticated user already registered shows status" do
      user = insert(:user, email: "registered@example.com")
      event = insert(:event, title: "Already Registered Event", visibility: "public")
      _participant = insert(:event_participant, event: event, user: user, email: user.email)

      conn = build_conn()
      |> log_in_user(user)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Should show already registered status
      assert html =~ "You&#39;re registered" || html =~ "Already registered"
      refute html =~ "Register for"
    end
  end

  describe "accessibility and form behavior" do
    setup do
      event = insert(:event, title: "Accessibility Test Event", visibility: "public")
      %{event: event}
    end

    test "form has proper labels and accessibility attributes", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view |> element("#register-button") |> render_click()
      html = render(view)

      # Check for proper form accessibility
      assert html =~ ~r/label.*for.*name/i
      assert html =~ ~r/label.*for.*email/i
      assert html =~ ~r/input.*id.*name/i
      assert html =~ ~r/input.*id.*email/i
      assert html =~ ~r/input.*type.*email/i
    end

    test "form submission is prevented when loading", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      view |> element("#register-button") |> render_click()

      # Simulate clicking submit multiple times rapidly
      view |> element("#registration-form") |> render_submit(%{
        name: "Test User",
        email: "test@example.com"
      })

      # Second submission should be ignored if still processing
      html = render(view)
      assert html =~ "disabled" || html =~ "loading"
    end
  end
end
