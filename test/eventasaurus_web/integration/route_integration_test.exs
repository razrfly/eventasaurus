defmodule EventasaurusWeb.RouteIntegrationTest do
  use EventasaurusWeb.ConnCase

  alias EventasaurusApp.Auth.TestClient

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

  describe "critical routes" do
    test "home page loads successfully", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Eventasaurus"
    end

    test "login page loads successfully", %{conn: conn} do
      conn = get(conn, ~p"/auth/login")
      assert html_response(conn, 200) =~ "Eventasaurus"
    end

    test "register page loads successfully", %{conn: conn} do
      conn = get(conn, ~p"/auth/register")
      assert html_response(conn, 200) =~ "Eventasaurus"
    end

    test "direct login route redirects correctly", %{conn: conn} do
      # /login should redirect to /auth/login
      conn = get(conn, "/login")
      assert redirected_to(conn) == "/auth/login"

      # Follow the redirect and verify the login page loads
      conn = get(conn, "/auth/login")
      assert html_response(conn, 200) =~ "Eventasaurus"
    end

    test "direct register route redirects correctly", %{conn: conn} do
      # /register should redirect to /auth/register
      conn = get(conn, "/register")
      assert redirected_to(conn) == "/auth/register"

      # Follow the redirect and verify the register page loads
      conn = get(conn, "/auth/register")
      assert html_response(conn, 200) =~ "Eventasaurus"
    end

    test "login form submission handles invalid credentials gracefully", %{conn: conn} do
      # Test that login form submission doesn't crash with undefined function error
      conn = post(conn, "/auth/login", %{
        "email" => "test@example.com",
        "password" => "wrongpassword"
      })

      # Should get a redirect or error page, not a 500 crash
      assert conn.status in [200, 302]
      # Should not crash with UndefinedFunctionError
      if conn.status == 200 do
        refute html_response(conn, 200) =~ "UndefinedFunctionError"
      end
    end

    test "login form with nested user params handles authentication gracefully", %{conn: conn} do
      # This tests the nested user params format that the actual form uses
      conn = post(conn, "/auth/login", %{
        "user" => %{
          "email" => "test@example.com",
          "password" => "wrongpassword",
          "remember_me" => "true"
        }
      })

      # Should not crash with ActionClauseError
      assert conn.status in [200, 302, 400]
      if conn.status == 200 do
        refute html_response(conn, 200) =~ "ActionClauseError"
      end
    end

    test "invalid auth routes return 404", %{conn: conn} do
      conn = get(conn, "/auth/sign_in")
      assert html_response(conn, 404)
    end

    test "dashboard requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/dashboard")
      assert redirected_to(conn) == ~p"/auth/login"
    end
  end

  describe "LiveView routes" do
    test "public event pages load for anonymous users", %{conn: conn} do
      # Create a test event
      user = EventasaurusApp.AccountsFixtures.user_fixture()
      event = EventasaurusApp.EventsFixtures.event_fixture(%{user_id: user.id})

      # Test that the public event page loads using slug
      conn = get(conn, ~p"/events/#{event.slug}")
      assert html_response(conn, 200) =~ event.title
    end

    test "authenticated routes redirect when not authenticated", %{conn: conn} do
      # Test that dashboard redirects to login when not authenticated
      conn = get(conn, ~p"/dashboard")
      assert redirected_to(conn) == ~p"/auth/login"
    end

    test "authenticated routes work with proper user assignment", %{conn: conn} do
      user = EventasaurusApp.AccountsFixtures.user_fixture()

      # Simulate authentication using the helper
      {conn, _token} = authenticate_user(conn, user)

      # Test that dashboard loads with authentication
      conn = get(conn, ~p"/dashboard")
      assert html_response(conn, 200) =~ "Dashboard"
    end
  end

  describe "event edit routes" do
    test "edit route redirects unauthenticated users to login", %{conn: conn} do
      event = EventasaurusApp.EventsFixtures.event_fixture()

      conn = get(conn, ~p"/events/#{event.slug}/edit")
      assert redirected_to(conn) == ~p"/auth/login"
    end

    test "edit route works for authenticated users who can manage the event", %{conn: conn} do
      user = EventasaurusApp.AccountsFixtures.user_fixture()
      event = EventasaurusApp.EventsFixtures.event_fixture(%{user: user})

      # Authenticate the user
      {conn, _token} = authenticate_user(conn, user)

      # Should be able to access edit page
      conn = get(conn, ~p"/events/#{event.slug}/edit")
      assert html_response(conn, 200) =~ "Edit Event"
    end
  end
end
