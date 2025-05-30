defmodule EventasaurusWeb.AuthHelpersTest do
  @moduledoc """
  Tests for authentication helpers in ConnCase.
  """

  use EventasaurusWeb.ConnCase, async: true

  setup do
    clear_test_auth()
    :ok
  end

  describe "authentication helpers" do
    test "log_in_user/2 authenticates a user", %{conn: conn} do
      user = insert(:user)

      conn = log_in_user(conn, user)

      # Verify the session contains the access token
      assert get_session(conn, "access_token") == "test_token_#{user.id}"
    end

    test "register_and_log_in_user/2 creates and authenticates a user", %{conn: conn} do
      {conn, user} = register_and_log_in_user(conn, %{name: "Test User"})

      # Verify user was created
      assert user.name == "Test User"
      assert user.email =~ "@example.com"

      # Verify user is authenticated
      assert get_session(conn, "access_token") == "test_token_#{user.id}"
    end

    test "log_in_event_organizer/3 creates organizer relationship", %{conn: conn} do
      event = insert(:event)

      {conn, user} = log_in_event_organizer(conn, event)

      # Verify user is authenticated
      assert get_session(conn, "access_token") == "test_token_#{user.id}"

      # Verify the user is an organizer of the event
      assert EventasaurusApp.Events.user_is_organizer?(event, user)
    end

    test "authentication works with authenticated routes", %{conn: conn} do
      user = insert(:user)
      conn = log_in_user(conn, user)

      # Try to access an authenticated route (dashboard)
      conn = get(conn, ~p"/dashboard")

      # Should not redirect to login
      assert html_response(conn, 200)
      # Should show user's email
      assert html_response(conn, 200) =~ user.email
    end

    test "unauthenticated access redirects to login", %{conn: conn} do
      # Try to access an authenticated route without authentication
      conn = get(conn, ~p"/dashboard")

      # Should redirect to login page
      assert redirected_to(conn) == "/auth/login"
    end
  end
end
