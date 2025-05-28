defmodule EventasaurusWeb.AuthenticationUXTest do
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

  describe "authentication user experience" do
    test "authenticated user sees their info in header", %{conn: conn} do
      user = EventasaurusApp.AccountsFixtures.user_fixture(%{
        name: "John Doe",
        email: "john@example.com"
      })

      # Authenticate the user
      {conn, _token} = authenticate_user(conn, user)

      # Visit dashboard
      conn = get(conn, ~p"/dashboard")
      response = html_response(conn, 200)

      # User should see their email in the header
      assert response =~ "john@example.com"

      # User should see sign out option
      assert response =~ "Log out"

      # User should NOT see sign in
      refute response =~ "Sign In"
    end

    test "anonymous user sees sign in options", %{conn: conn} do
      # Visit home page as anonymous user
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)

      # Should see sign in option in header
      assert response =~ "Sign In"

      # Should NOT see user-specific content in header
      refute response =~ "Log out"
      # Check that no user email appears in the header/nav area specifically
      # (avoiding false positives from footer content)
      header_section = response
        |> String.split("<main")
        |> List.first()
      refute header_section =~ ~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/
    end

    test "user state persists across pages", %{conn: conn} do
      user = EventasaurusApp.AccountsFixtures.user_fixture(%{
        name: "Jane Smith",
        email: "jane@example.com"
      })

      # Authenticate the user
      {conn, _token} = authenticate_user(conn, user)

      # Check multiple pages for consistent user state
      pages = [~p"/", ~p"/dashboard", ~p"/about"]

      for page <- pages do
        conn = get(conn, page)
        response = html_response(conn, 200)

        # Should see user email on all pages
        assert response =~ "jane@example.com", "User email missing on #{page}"

        # Should see logout on all pages
        assert response =~ "Log out", "Logout missing on #{page}"

        # Should NOT see sign in on any page
        refute response =~ "Sign In", "Sign In should not appear on #{page} when authenticated"
      end
    end

    test "complete authentication flow", %{conn: conn} do
      # Start as anonymous user
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ "Sign In"
      refute response =~ "Log out"

      # Try to access protected page - should redirect
      conn = get(conn, ~p"/dashboard")
      assert redirected_to(conn) == ~p"/auth/login"

      # Go to login page
      conn = get(conn, ~p"/auth/login")
      assert html_response(conn, 200) =~ "Eventasaurus"

      # TODO: Complete login flow when we fix the authentication
      # For now, this test documents what should happen
    end
  end
end
