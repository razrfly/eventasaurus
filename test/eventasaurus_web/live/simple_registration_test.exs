defmodule EventasaurusWeb.SimpleRegistrationTest do
  @moduledoc """
  Simple test to identify the registration flow issue
  """

  use EventasaurusWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  test "new user registration with mock - test current behavior", %{conn: conn} do
    event = insert(:event, title: "Test Event", visibility: "public")

    # Mock Supabase API calls for new user (OTP flow)
    EventasaurusApp.HTTPoison.Mock
    |> expect(:get, fn _url, _headers ->
      {:ok, %HTTPoison.Response{
        status_code: 200,
        body: Jason.encode!(%{"users" => []})  # No existing user
      }}
    end)
        |> expect(:post, fn _url, body, _headers ->
      parsed_body = Jason.decode!(body)
      # Verify the OTP request structure
      assert parsed_body["email"] == "test@example.com"
      assert parsed_body["options"]["shouldCreateUser"] == true
      assert parsed_body["data"]["name"] == "Test User"

      {:ok, %HTTPoison.Response{
        status_code: 200,
        body: Jason.encode!(%{"email" => "test@example.com", "sent_at" => "2024-01-01T00:00:00Z"})
      }}
    end)

        # Visit the event page using the public route (slug, not /events/slug)
    {:ok, view, html} = live(conn, ~p"/#{event.slug}")

    # Check what registration status is displayed
    assert has_element?(view, "#register-now-btn")

    # Click register button to open modal
    view |> element("#register-now-btn") |> render_click()

    # Verify modal is shown
    assert has_element?(view, "#registration-form")

    # Fill out and submit form
    view
    |> form("#registration-form", registration: %{name: "Test User", email: "test@example.com"})
    |> render_submit()

        # Check current state
    final_html = render(view)

    # Verify the expected behavior
    assert String.contains?(final_html, "Check Your Email"), "Should show email confirmation message"
    assert String.contains?(final_html, "test@example.com"), "Should show the email address"
    assert String.contains?(final_html, "Click the link in your email"), "Should show instructions"
    refute String.contains?(final_html, "Register for Event"), "Registration button should be hidden"

    # Verify the registration status changed
    assert has_element?(view, "[data-testid='email-confirmation-pending']") ||
           String.contains?(final_html, "Check Your Email")
  end
end
