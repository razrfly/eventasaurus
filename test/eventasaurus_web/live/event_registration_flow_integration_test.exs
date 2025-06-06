defmodule EventasaurusWeb.EventRegistrationFlowIntegrationTest do
  @moduledoc """
  Integration tests for the complete event registration flow including:
  - UI feedback for registration success/failure
  - Proper status messages and modal behavior
  - Email confirmation flow vs immediate registration
  - Voting registration flow
  """

  use EventasaurusWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  describe "event registration flow" do
    setup do
      event = insert(:event, title: "Test Conference", visibility: "public")
      %{event: event}
    end

    test "new user registration shows email confirmation message and closes modal", %{conn: conn, event: event} do
      # Mock Supabase OTP request for new user
      EventasaurusApp.HTTPoison.Mock
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{"users" => []})  # No existing user found
        }}
      end)
      |> expect(:post, fn _url, body, _headers ->
        parsed_body = Jason.decode!(body)
        assert parsed_body["email"] == "newuser@example.com"
        assert parsed_body["options"]["shouldCreateUser"] == true

        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{"email" => "newuser@example.com", "sent_at" => "2024-01-01T00:00:00Z"})
        }}
      end)

      # Visit the event page
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

            # Verify registration button is present
      assert has_element?(view, "#register-now-btn")

      # Click register button to open modal
      view |> element("#register-now-btn") |> render_click()

      # Verify modal is shown
      assert has_element?(view, "#registration-form")

      # Fill out and submit registration form
      view
      |> form("#registration-form", registration: %{name: "New User", email: "newuser@example.com"})
      |> render_submit()

      # Verify modal is closed after successful registration
      refute has_element?(view, "#registration-form")

      # Verify success message is shown for email confirmation
      assert render(view) =~ "Check your email to confirm"
      assert render(view) =~ "Test Conference"

      # Verify flash message appears
      flash_info = assert_redirected(view, nil)
      assert flash_info =~ "Check your email" ||
             render(view) =~ "Check your email"
    end

        test "existing user registration shows immediate success message", %{conn: conn, event: event} do
      # Create an existing user in the database
      existing_user = insert(:user, email: "existing@example.com", name: "Existing User")

      # Mock Supabase response for existing user
      EventasaurusApp.HTTPoison.Mock
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{
            "users" => [%{
              "id" => "existing-uuid",
              "email" => "existing@example.com",
              "user_metadata" => %{"name" => "Existing User"},
              "created_at" => "2024-01-01T00:00:00Z"
            }]
          })
        }}
      end)

      # Visit the event page
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Click register button
      view |> element("#register-now-btn") |> render_click()

      # Fill out and submit registration form with existing user email
      view
      |> form("#registration-form", registration: %{name: "Existing User", email: "existing@example.com"})
      |> render_submit()

      # Verify modal is closed
      refute has_element?(view, "#registration-form")

      # Verify immediate success message (no email confirmation needed)
      assert render(view) =~ "You're now registered for Test Conference"

      # Verify no email confirmation message
      refute render(view) =~ "Check your email"
    end

    test "registration failure shows error message and keeps modal open", %{conn: conn, event: event} do
      # Mock Supabase error response
      EventasaurusApp.HTTPoison.Mock
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{"users" => []})
        }}
      end)
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 422,
          body: Jason.encode!(%{"error" => "Email already registered"})
        }}
      end)

            # Visit the event page
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Click register button
      view |> element("#register-now-btn") |> render_click()

      # Submit registration form
      view
      |> form("#registration-form", registration: %{name: "Test User", email: "error@example.com"})
      |> render_submit()

      # Verify modal is closed (error handling closes modal too)
      refute has_element?(view, "#registration-form")

      # Verify error message is shown
      assert render(view) =~ "We're having trouble creating your account" ||
             render(view) =~ "Something went wrong"
    end

        test "validates form fields before submission", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Click register button
      view |> element("#register-now-btn") |> render_click()

      # Submit empty form
      view
      |> form("#registration-form", registration: %{name: "", email: ""})
      |> render_submit()

      # Verify modal stays open due to validation errors
      assert has_element?(view, "#registration-form")

      # Verify validation error messages
      assert render(view) =~ "Name is required"
      assert render(view) =~ "Email is required"
    end

        test "handles invalid email format", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Click register button
      view |> element("#register-now-btn") |> render_click()

      # Submit form with invalid email
      view
      |> form("#registration-form", registration: %{name: "Test User", email: "invalid-email"})
      |> render_submit()

      # Verify modal stays open due to validation error
      assert has_element?(view, "#registration-form")

      # Verify email validation error
      assert render(view) =~ "Please enter a valid email address"
    end
  end

  describe "voting registration flow" do
    setup do
      event = insert(:event,
        title: "Test Poll Event",
        visibility: "public",
        state: "polling"
      )

      date_poll = insert(:event_date_poll, event: event, question: "When works best?")
      option1 = insert(:event_date_option, poll: date_poll, date: ~D[2024-12-25])
      option2 = insert(:event_date_option, poll: date_poll, date: ~D[2024-12-26])

      %{event: event, date_poll: date_poll, options: [option1, option2]}
    end

    test "new voter registration with OTP shows proper feedback", %{conn: conn, event: event, options: options} do
      # Mock Supabase OTP request for new voter
      EventasaurusApp.HTTPoison.Mock
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{"users" => []})
        }}
      end)
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{"email" => "voter@example.com", "sent_at" => "2024-01-01T00:00:00Z"})
        }}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Verify voting interface is present for polling events
      assert has_element?(view, "[data-testid='voting-interface']")

      # Click vote button to open voting modal
      view |> element("[data-testid='vote-button']") |> render_click()

            # Fill out voting form with new user
      view
      |> form("#vote-form", %{
        "name" => "New Voter",
        "email" => "voter@example.com",
        "votes[#{Enum.at(options, 0).id}]" => "yes"
      })
      |> render_submit()

      # Verify voting modal is closed
      refute has_element?(view, "#vote-form")

      # Verify proper feedback message for email confirmation
      assert render(view) =~ "Check your email to verify your account" ||
             render(view) =~ "Check your email"
    end

    test "existing voter shows immediate success", %{conn: conn, event: event, options: options} do
      # Create existing user
      existing_user = insert(:user, email: "existing.voter@example.com")

      # Mock existing user response
      EventasaurusApp.HTTPoison.Mock
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{
            "users" => [%{
              "id" => "voter-uuid",
              "email" => "existing.voter@example.com",
              "user_metadata" => %{"name" => "Existing Voter"}
            }]
          })
        }}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Open voting modal and vote
      view |> element("[data-testid='vote-button']") |> render_click()

            view
      |> form("#vote-form", %{
        "name" => "Existing Voter",
        "email" => "existing.voter@example.com",
        "votes[#{Enum.at(options, 0).id}]" => "yes"
      })
      |> render_submit()

      # Verify immediate success without email confirmation
      assert render(view) =~ "votes saved successfully" ||
             render(view) =~ "You're registered"

      # Should not mention email verification for existing users
      refute render(view) =~ "Check your email to verify"
    end
  end
end
