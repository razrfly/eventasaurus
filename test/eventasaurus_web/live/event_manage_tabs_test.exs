defmodule EventasaurusWeb.EventManageTabsTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  setup %{conn: conn} do
    # Create test event and organizer
    organizer = user_fixture(%{name: "Event Organizer", email: "organizer@example.com"})
    event = event_fixture(%{title: "Test Event", organizers: [organizer]})

    # Authenticate as the organizer
    conn = log_in_user(conn, organizer)

    %{
      conn: conn,
      event: event,
      organizer: organizer
    }
  end

  describe "tab navigation" do
    test "default route redirects to overview tab", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}")
      
      # Should be on overview tab by default
      assert html =~ "border-blue-500 text-blue-600"
      assert html =~ "Overview"
      
      # Check that we're showing overview content
      assert html =~ "Event Stats"
    end

    test "can navigate directly to guests tab", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}/guests")
      
      # Should be on guests tab
      assert html =~ "Guests"
      # Check for guests-specific content markers
      assert html =~ "Invite Guests" or html =~ "Guest List"
    end

    test "can navigate directly to registrations tab", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}/registrations")
      
      # Should be on registrations tab (note: renamed from "registration")
      assert html =~ "Registrations"
      # Check for registration-specific content
      assert html =~ "Registration Settings" or html =~ "Ticket"
    end

    test "can navigate directly to polls tab", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}/polls")
      
      # Should be on polls tab
      assert html =~ "Polls"
      # Polls content loads dynamically, so just check the tab is active
    end

    test "can navigate directly to insights tab", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}/insights")
      
      # Should be on insights tab
      assert html =~ "Insights"
      # Check for insights-specific content
      assert html =~ "Analytics" or html =~ "Refresh"
    end

    test "clicking tab navigates to correct URL", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")
      
      # Click on guests tab
      view
      |> element("button[phx-value-tab='guests']")
      |> render_click()
      
      # Should navigate to guests URL
      assert_redirect(view, ~p"/events/#{event.slug}/guests")
    end

    test "tab state persists through navigation", %{conn: conn, event: event} do
      # Navigate to polls tab
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/polls")
      
      # Navigate away and back
      view
      |> element("button[phx-value-tab='insights']")
      |> render_click()
      
      assert_redirect(view, ~p"/events/#{event.slug}/insights")
      
      # Go back to polls - should still be on polls tab
      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}/polls")
      assert html =~ "Polls"
    end

    test "all tab names are plural", %{conn: conn, event: event} do
      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}")
      
      # Check that all tab names are plural
      assert html =~ "Guests"
      assert html =~ "Registrations"  # Changed from "Registration"
      assert html =~ "Polls"
      assert html =~ "Insights"
      
      # Make sure we don't have the singular "registration" tab
      refute has_element?(view, "button[phx-value-tab='registration']")
      assert has_element?(view, "button[phx-value-tab='registrations']")
    end
  end

  describe "authorization" do
    test "non-organizer cannot access event management", %{conn: conn, event: event} do
      # Create and login as a different user
      other_user = user_fixture(%{name: "Other User", email: "other@example.com"})
      conn = log_in_user(conn, other_user)
      
      {:error, {:redirect, %{to: "/dashboard", flash: flash}}} = 
        live(conn, ~p"/events/#{event.slug}")
      
      assert flash["error"] =~ "don't have permission"
    end

    test "unauthenticated user is redirected to login", %{event: event} do
      conn = build_conn()
      
      {:error, {:redirect, %{to: "/auth/login", flash: flash}}} = 
        live(conn, ~p"/events/#{event.slug}")
      
      assert flash["error"] =~ "must be logged in"
    end
  end
end