defmodule EventasaurusWeb.PublicEventLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts

  describe "mount" do
    test "loads event successfully for anonymous user", %{conn: conn} do
      event = event_fixture()

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      assert html =~ event.title
      assert html =~ "Register Now"
    end

    test "loads event successfully for authenticated user not registered", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      assert html =~ event.title
      assert html =~ "One-Click Register"
      assert html =~ user.name
      assert html =~ user.email
    end

    test "loads event successfully for registered user", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Create registration
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      assert html =~ event.title
      assert html =~ "You're In"
      assert html =~ "Add to Calendar"
      assert html =~ "Cancel registration"
    end

    test "loads event successfully for cancelled user", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Create cancelled registration
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      assert html =~ event.title
      assert html =~ "You're Not Going"
      assert html =~ "Register Again"
    end

    test "loads event successfully for organizer", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Add user as organizer
      {:ok, _} = Events.add_user_to_event(event, user)

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      assert html =~ event.title
      assert html =~ "Event Organizer"
      assert html =~ "Manage Event"
    end

    test "redirects for non-existent event", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/non-existent-event")

      assert_redirected(conn, ~p"/")
    end

    test "redirects for reserved slug", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/admin")

      assert_redirected(conn, ~p"/")
    end
  end

  describe "one_click_register event" do
    test "successfully registers authenticated user", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Click one-click register
      view |> element("button", "One-Click Register") |> render_click()

      # Should show success message and update UI
      assert render(view) =~ "You're In"
      assert render(view) =~ "You're now registered"

      # Verify registration in database
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant != nil
      assert participant.status == :pending
      assert participant.source == "one_click_registration"
    end

    test "shows error for already registered user", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Create existing registration
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Should show "You're In" state, not one-click register
      assert render(view) =~ "You're In"
      refute render(view) =~ "One-Click Register"
    end

    test "shows error for organizer attempting registration", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Add user as organizer
      {:ok, _} = Events.add_user_to_event(event, user)

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Should show organizer state, not registration options
      assert render(view) =~ "Event Organizer"
      refute render(view) =~ "One-Click Register"
    end
  end

  describe "cancel_registration event" do
    test "successfully cancels registration", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Create registration
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Should show registered state
      assert render(view) =~ "You're In"

      # Cancel registration (note: this would normally show a confirmation dialog)
      view |> element("button", "Cancel registration") |> render_click()

      # Should show cancelled state
      assert render(view) =~ "You're Not Going"
      assert render(view) =~ "Your registration has been cancelled"

      # Verify cancellation in database
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant.status == :cancelled
    end

    test "shows error when trying to cancel non-existent registration", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Simulate authenticated user (no registration)
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Should show not registered state
      assert render(view) =~ "One-Click Register"

      # Try to cancel (this would be an edge case)
      view |> element("button", "cancel_registration") |> render_click()

      assert render(view) =~ "You're not registered for this event"
    end
  end

  describe "reregister event" do
    test "successfully re-registers cancelled user", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Create cancelled registration
      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Should show cancelled state
      assert render(view) =~ "You're Not Going"

      # Re-register
      view |> element("button", "Register Again") |> render_click()

      # Should show registered state
      assert render(view) =~ "You're In"
      assert render(view) =~ "Welcome back"

      # Verify re-registration in database
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant.status == :pending
      assert participant.metadata[:reregistered_at] != nil
    end
  end

  describe "show_registration_modal event" do
    test "opens registration modal for anonymous user", %{conn: conn} do
      event = event_fixture()

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Should show register now button
      assert render(view) =~ "Register Now"

      # Click register now
      view |> element("button", "Register Now") |> render_click()

      # Should show registration modal
      assert render(view) =~ "registration-modal"
    end
  end

  describe "registration success handling" do
    test "handles new registration success message", %{conn: conn} do
      event = event_fixture()

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Simulate registration success message
      send(view.pid, {:registration_success, :new_registration, "John Doe", "john@example.com"})

      # Should show success message and update state
      assert render(view) =~ "Welcome! You're now registered"
      assert render(view) =~ "Check your email for account verification"
    end

    test "handles existing user registration success message", %{conn: conn} do
      event = event_fixture()

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Simulate existing user registration success
      send(view.pid, {:registration_success, :existing_user_registered, "Jane Doe", "jane@example.com"})

      # Should show success message without email verification
      assert render(view) =~ "Great! You're now registered"
      refute render(view) =~ "Check your email for account verification"
    end

    test "handles registration error message", %{conn: conn} do
      event = event_fixture()

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Simulate registration error
      send(view.pid, {:registration_error, :already_registered})

      # Should show error message
      assert render(view) =~ "You're already registered for this event"
    end
  end

  describe "email verification display logic" do
    test "shows email verification for new registrations only", %{conn: conn} do
      event = event_fixture()
      user = user_fixture()

      # Simulate authenticated user
      conn = assign(conn, :current_user, %{
        "id" => user.supabase_id,
        "email" => user.email,
        "user_metadata" => %{"name" => user.name}
      })

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # One-click register (existing user)
      view |> element("button", "One-Click Register") |> render_click()

      # Should NOT show email verification for existing users
      refute render(view) =~ "Please verify your email"

      # But should show "You're In" state
      assert render(view) =~ "You're In"
    end
  end
end
