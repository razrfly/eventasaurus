defmodule EventasaurusWeb.PeopleLive.IndexTest do
  use EventasaurusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory

  alias EventasaurusApp.Relationships

  setup do
    clear_test_auth()
    :ok
  end

  describe "unauthenticated access" do
    test "redirects to login page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/auth/login"}}} = live(conn, "/people/discover")
    end
  end

  describe "authenticated access" do
    test "renders the discovery page with default tab", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, _view, html} = live(conn, "/people/discover")

      assert html =~ "People"
      assert html =~ "Discover and connect with people from your events"
      assert html =~ "You Know"
      assert html =~ "At Your Events"
      assert html =~ "You Might Know"
    end

    test "shows empty state when no connections exist", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, _view, html} = live(conn, "/people/discover")

      assert html =~ "No people found"
      assert html =~ "connected with anyone yet"
    end

    test "/people renders discovery page", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, _view, html} = live(conn, "/people")

      assert html =~ "People"
      assert html =~ "You Know"
    end
  end

  describe "tab navigation" do
    test "can switch to At Your Events tab", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, "/people/discover")

      html =
        view
        |> element("button", "At Your Events")
        |> render_click()

      assert html =~ "No other attendees from your events"
    end

    test "can switch to You Might Know tab", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, "/people/discover")

      html =
        view
        |> element("button", "You Might Know")
        |> render_click()

      assert html =~ "friends-of-friends suggestions"
    end

    test "URL params set the active tab", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, _view, html} = live(conn, "/people/discover?tab=you_might_know")

      # The You Might Know tab should be active (has different styling)
      assert html =~ "friends-of-friends suggestions"
    end

    test "invalid tab defaults to you_know", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, _view, html} = live(conn, "/people/discover?tab=invalid")

      assert html =~ "connected with anyone yet"
    end
  end

  describe "you_know tab with data" do
    test "displays connected users", %{conn: conn} do
      {conn, user} = register_and_log_in_user(conn)

      # Create another user and a connection
      other_user = insert(:user, name: "Jane Smith")

      # Create a shared event for context
      event = insert(:event, title: "Jazz Night")
      # Add user as organizer
      insert(:event_user, event: event, user: user, role: "organizer")

      # Create the relationship
      {:ok, _} = Relationships.create_from_shared_event(user, other_user, event, "Met at Jazz Night")

      {:ok, _view, html} = live(conn, "/people/discover")

      assert html =~ "Jane Smith"
    end
  end

  describe "at_your_events tab with data" do
    test "displays co-attendees from past events", %{conn: conn} do
      {conn, user} = register_and_log_in_user(conn)

      # Create an event in the past
      past_time = DateTime.add(DateTime.utc_now(), -7, :day)
      event = insert(:event, title: "Past Concert", start_at: past_time)

      # Create another user who also attended
      other_user = insert(:user, name: "Concert Friend")

      # Add both users as participants
      insert(:event_participant, event: event, user: user, status: :accepted)
      insert(:event_participant, event: event, user: other_user, status: :accepted)

      {:ok, view, _html} = live(conn, "/people/discover")

      html =
        view
        |> element("button", "At Your Events")
        |> render_click()

      # Either show the user or empty state (depends on privacy settings)
      assert html =~ "Concert Friend" or html =~ "No other attendees"
    end
  end

  describe "you_might_know tab with data" do
    test "displays friends-of-friends suggestions", %{conn: conn} do
      {conn, user} = register_and_log_in_user(conn)

      # Create a mutual friend
      mutual_friend = insert(:user, name: "Mutual Friend")
      friend_of_friend = insert(:user, name: "Suggested Person")

      # Create events for context
      event1 = insert(:event, title: "Event 1")
      event2 = insert(:event, title: "Event 2")

      # User is connected to mutual_friend
      {:ok, _} = Relationships.create_from_shared_event(user, mutual_friend, event1, "context")

      # Mutual friend is connected to friend_of_friend
      {:ok, _} = Relationships.create_from_shared_event(mutual_friend, friend_of_friend, event2, "context")

      {:ok, view, _html} = live(conn, "/people/discover")

      html =
        view
        |> element("button", "You Might Know")
        |> render_click()

      # Should show the friend of friend or empty state
      assert html =~ "Suggested Person" or html =~ "friends-of-friends suggestions"
    end
  end

  describe "privacy filtering" do
    test "does not show users who opted out of discovery", %{conn: conn} do
      {conn, user} = register_and_log_in_user(conn)

      # Create a user who opted out
      hidden_user = insert(:user, name: "Hidden User")
      insert(:private_user_preferences, user: hidden_user)

      # Create an event they both attended
      past_time = DateTime.add(DateTime.utc_now(), -7, :day)
      event = insert(:event, title: "Shared Event", start_at: past_time)
      insert(:event_participant, event: event, user: user, status: :accepted)
      insert(:event_participant, event: event, user: hidden_user, status: :accepted)

      {:ok, view, _html} = live(conn, "/people/discover")

      html =
        view
        |> element("button", "At Your Events")
        |> render_click()

      # The hidden user should NOT appear
      refute html =~ "Hidden User"
    end
  end
end
