defmodule EventasaurusWeb.ProfileControllerTest do
  use EventasaurusWeb.ConnCase

  alias EventasaurusApp.Accounts

  describe "GET /user/:username" do
    test "shows public profile for existing user", %{conn: conn} do
      user = user_fixture(%{
        username: "publicuser",
        name: "Public User",
        bio: "This is my bio",
        profile_public: true
      })

      conn = get(conn, ~p"/user/publicuser")

      assert html_response(conn, 200) =~ "Public User"
      assert html_response(conn, 200) =~ "@publicuser"
      assert html_response(conn, 200) =~ "This is my bio"
    end

    test "shows own private profile when authenticated", %{conn: conn} do
      user = user_fixture(%{
        username: "privateuser",
        name: "Private User",
        profile_public: false
      })

      # Properly authenticate user for viewing their own profile
      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/user/privateuser")

      assert html_response(conn, 200) =~ "Private User"
      assert html_response(conn, 200) =~ "@privateuser"
      assert html_response(conn, 200) =~ "Edit Profile"
    end

    test "returns 404 for private profile when not authenticated", %{conn: conn} do
      user = user_fixture(%{
        username: "privateuser",
        name: "Private User",
        profile_public: false
      })

      conn = get(conn, ~p"/user/privateuser")

      assert html_response(conn, 404) =~ "User not found"
    end

    test "returns 404 for private profile when authenticated as different user", %{conn: conn} do
      _private_user = user_fixture(%{
        username: "privateuser",
        name: "Private User",
        profile_public: false
      })

      other_user = user_fixture(%{
        username: "otheruser",
        name: "Other User"
      })

      # Authenticate as different user trying to view private profile
      conn = log_in_user(conn, other_user)
      conn = get(conn, ~p"/user/privateuser")

      assert html_response(conn, 404) =~ "User not found"
    end

    test "returns 404 for non-existent user", %{conn: conn} do
      conn = get(conn, ~p"/user/nonexistentuser")

      assert html_response(conn, 404) =~ "User not found"
    end

    test "handles case-insensitive username lookup", %{conn: conn} do
      user = user_fixture(%{
        username: "casetest",
        name: "Case Test User",
        profile_public: true
      })

      # Test uppercase
      conn = get(conn, ~p"/user/CASETEST")
      assert html_response(conn, 200) =~ "Case Test User"

      # Test mixed case
      conn = get(conn, ~p"/user/CaseTest")
      assert html_response(conn, 200) =~ "Case Test User"
    end

    test "displays social media links when present", %{conn: conn} do
      user = user_fixture(%{
        username: "socialuser",
        name: "Social User",
        profile_public: true,
        instagram_handle: "myinstagram",
        x_handle: "mytwitter",
        website_url: "https://example.com"
      })

      conn = get(conn, ~p"/user/socialuser")
      response = html_response(conn, 200)

      assert response =~ "Instagram"
      assert response =~ "myinstagram"
      assert response =~ "X"
      assert response =~ "mytwitter"
      assert response =~ "https://example.com"
    end

    test "shows private profile notice for own private profile", %{conn: conn} do
      user = user_fixture(%{
        username: "privateowner",
        name: "Private Owner",
        profile_public: false
      })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/user/privateowner")

      response = html_response(conn, 200)
      assert response =~ "Private Profile"
      assert response =~ "Only you can see this profile"
    end
  end

  describe "GET /u/:username" do
    test "redirects to full profile URL for existing public user", %{conn: conn} do
      user = user_fixture(%{
        username: "redirectuser",
        profile_public: true
      })

      conn = get(conn, ~p"/u/redirectuser")

      assert redirected_to(conn, 302) == "/user/redirectuser"
    end

    test "redirects to full profile URL for existing private user when authenticated", %{conn: conn} do
      user = user_fixture(%{
        username: "redirectprivate",
        profile_public: false
      })

      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/u/redirectprivate")

      assert redirected_to(conn, 302) == "/user/redirectprivate"
    end

    test "returns 404 for non-existent user", %{conn: conn} do
      conn = get(conn, ~p"/u/nonexistentuser")

      assert html_response(conn, 404) =~ "User not found"
    end

    test "returns 404 for private user when not authenticated", %{conn: conn} do
      user = user_fixture(%{
        username: "privateredirect",
        profile_public: false
      })

      conn = get(conn, ~p"/u/privateredirect")

      assert html_response(conn, 404) =~ "User not found"
    end
  end

  # Helper function to create users for testing
  defp user_fixture(attrs \\ %{}) do
    default_attrs = %{
      email: "test#{System.unique_integer()}@example.com",
      name: "Test User",
      supabase_id: "test_#{System.unique_integer()}"
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, user} = Accounts.create_user(attrs)
    user
  end
end
