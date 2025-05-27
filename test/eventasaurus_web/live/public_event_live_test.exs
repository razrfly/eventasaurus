defmodule EventasaurusWeb.PublicEventLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Events
  alias EventasaurusApp.Auth.TestClient

  setup do
    event = event_fixture()

    # Clean up any existing test users
    TestClient.clear_test_users()

    %{event: event}
  end

  # Helper function to simulate authenticated user session
  defp authenticate_user(conn, user) do
    # Create a test token
    token = "test_token_#{user.id}"

    # Set up the mock user data that the TestClient will return
    # Convert the User struct to the format that Supabase would return
    supabase_user = %{
      "id" => user.supabase_id,
      "email" => user.email,
      "user_metadata" => %{"name" => user.name}
    }
    TestClient.set_test_user(token, supabase_user)

    # Add the token to the session
    conn = conn |> Plug.Test.init_test_session(%{"access_token" => token})
    {conn, token}
  end

  # Helper function to create a registration for testing
  defp registration_fixture(attrs) do
    event_participant_fixture(attrs)
  end

  describe "Phase 1: Basic State Display Tests" do
    test "anonymous user shows register button", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show Register Now button for anonymous users
      assert html =~ "Register Now"
      # Should NOT show One-Click Register
      refute html =~ "One-Click Register"
      # Should show registration card title
      assert html =~ "Register for this event"
    end

    test "authenticated user not registered shows one-click register", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show user info
      assert html =~ user.name
      assert html =~ user.email
      # Should show One-Click Register button
      assert html =~ "One-Click Register"
      # Should NOT show Register Now
      refute html =~ "Register Now"
    end

    test "registered user shows you're in status", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Create an accepted registration for this user (accepted = registered)
      registration_fixture(%{event_id: event.id, user_id: user.id, status: :accepted})

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show You're In status (HTML entity encoded)
      assert html =~ "You&#39;re In"
      assert html =~ "You&#39;re registered for this event"
      # Should NOT show register buttons
      refute html =~ "Register Now"
      refute html =~ "One-Click Register"
      # Should show Cancel registration option (HTML entity encoded)
      assert html =~ "Can&#39;t attend? Cancel registration"
    end

    test "cancelled user shows you're not going status", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Create a cancelled registration for this user
      registration_fixture(%{event_id: event.id, user_id: user.id, status: :cancelled})

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show You're Not Going status (HTML entity encoded)
      assert html =~ "You&#39;re Not Going"
      assert html =~ "We hope to see you next time!"
      # Should show Register Again button
      assert html =~ "Register Again"
      # Should NOT show other registration buttons
      refute html =~ "Register Now"
      refute html =~ "One-Click Register"
    end

    test "event organizer shows organizer status", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Make this user the organizer by adding them to event.users
      # First remove existing organizer, then add our test user
      Events.remove_user_from_event(event, hd(event.users))
      Events.add_user_to_event(event, user)

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show Event Organizer status
      assert html =~ "Event Organizer"
      assert html =~ "You&#39;re hosting this event"
      # Should NOT show register buttons
      refute html =~ "Register Now"
      refute html =~ "One-Click Register"
      refute html =~ "Register Again"
      # Should show management options
      assert html =~ "Manage Event"
    end
  end

  describe "Phase 2: Interactive Functionality Tests" do
    test "anonymous user registration modal opens", %{conn: conn, event: event} do
      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show Register Now button
      assert html =~ "Register Now"
      assert has_element?(view, "#register-now-btn")
      # Should not show the modal initially
      refute has_element?(view, "#registration-modal")

      # Click the Register Now button using the phx-click event
      html = render_click(view, "show_registration_modal")

      # Should show the registration modal component with unique text
      assert html =~ "Register for Event"
      assert html =~ "Your Info"
      assert html =~ "We&#39;ll create an account for you"
      # Should contain form elements for registration
      assert html =~ "registration[name]"
      assert html =~ "registration[email]"
    end

    test "one-click register works", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show One-Click Register button
      assert html =~ "One-Click Register"

      # Click the One-Click Register button
      html = render_click(view, "one_click_register")

      # Should show registration success
      assert html =~ "You&#39;re In"
      assert html =~ "You&#39;re registered for this event"
      # Should no longer show registration buttons
      refute html =~ "One-Click Register"
      refute html =~ "Register Now"
    end

    test "cancel registration works", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Create a registration for this user first
      registration_fixture(%{event_id: event.id, user_id: user.id, status: :accepted})

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show registered status
      assert html =~ "You&#39;re In"
      assert html =~ "Can&#39;t attend? Cancel registration"

      # Click the cancel registration button
      html = render_click(view, "cancel_registration")

      # Should show cancelled status
      assert html =~ "You&#39;re Not Going"
      assert html =~ "We hope to see you next time!"
      assert html =~ "Register Again"
      # Should no longer show registered status
      refute html =~ "You&#39;re In"
    end

    test "re-register works for cancelled user", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Create a cancelled registration for this user
      registration_fixture(%{event_id: event.id, user_id: user.id, status: :cancelled})

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show cancelled status
      assert html =~ "You&#39;re Not Going"
      assert html =~ "Register Again"

      # Click the Register Again button
      html = render_click(view, "reregister")

      # Should show registered status
      assert html =~ "You&#39;re In"
      assert html =~ "You&#39;re registered for this event"
      # Should no longer show cancelled status
      refute html =~ "You&#39;re Not Going"
      refute html =~ "Register Again"
    end

    test "registration modal contains required form elements", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Open the registration modal
      html = render_click(view, "show_registration_modal")
      
      # Verify the modal opens and contains all required form elements
      assert html =~ "Register for Event"
      assert html =~ "Your Info"
      assert html =~ "We&#39;ll create an account for you so you can manage your registration."
      
      # Check form elements are present
      assert has_element?(view, "form#registration-form")
      assert has_element?(view, "input[name='registration[name]']")
      assert has_element?(view, "input[name='registration[email]']")
      assert has_element?(view, "button[type='submit']")
      
      # Check that the form has proper attributes for component targeting
      assert html =~ "phx-submit=\"submit\""
      assert html =~ "phx-change=\"validate\""
      
      # Verify the modal can be interacted with
      assert has_element?(view, "button", "Register for Event")
    end
  end
end
