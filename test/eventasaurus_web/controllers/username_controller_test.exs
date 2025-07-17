defmodule EventasaurusWeb.UsernameControllerTest do
  use EventasaurusWeb.ConnCase

  alias EventasaurusApp.Accounts

  describe "GET /api/username/availability/:username" do
    test "returns available for valid unique username", %{conn: conn} do
      conn = get(conn, ~p"/api/username/availability/testuser123")

      assert json_response(conn, 200) == %{
               "available" => true,
               "valid" => true,
               "username" => "testuser123",
               "errors" => [],
               "suggestions" => []
             }
    end

    test "returns unavailable for existing username", %{conn: conn} do
      # Create a user first
      _user = user_fixture(%{username: "existinguser"})

      conn = get(conn, ~p"/api/username/availability/existinguser")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert response["valid"] == true
      assert response["username"] == "existinguser"
      assert "This username is already taken" in response["errors"]
      assert length(response["suggestions"]) > 0
    end

    test "returns unavailable for reserved username", %{conn: conn} do
      conn = get(conn, ~p"/api/username/availability/admin")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert response["valid"] == false
      assert response["username"] == "admin"
      assert "This username is reserved and cannot be used" in response["errors"]
      assert length(response["suggestions"]) > 0
    end

    test "returns invalid for username that's too short", %{conn: conn} do
      conn = get(conn, ~p"/api/username/availability/ab")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert response["valid"] == false
      assert response["username"] == "ab"

      assert "Username must be 3-30 characters and contain only letters, numbers, underscores, and hyphens" in response[
               "errors"
             ]

      # No suggestions for invalid format
      assert response["suggestions"] == []
    end

    test "returns invalid for username that's too long", %{conn: conn} do
      long_username = String.duplicate("a", 31)
      conn = get(conn, ~p"/api/username/availability/#{long_username}")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert response["valid"] == false
      assert response["username"] == long_username

      assert "Username must be 3-30 characters and contain only letters, numbers, underscores, and hyphens" in response[
               "errors"
             ]
    end

    test "returns invalid for username with invalid characters", %{conn: conn} do
      conn = get(conn, ~p"/api/username/availability/test@user")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert response["valid"] == false
      assert response["username"] == "test@user"

      assert "Username must be 3-30 characters and contain only letters, numbers, underscores, and hyphens" in response[
               "errors"
             ]
    end

    test "returns invalid for empty username", %{conn: conn} do
      conn = get(conn, ~p"/api/username/availability/ ")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert response["valid"] == false
      assert "Username cannot be empty" in response["errors"]
    end

    test "handles case-insensitive username conflicts", %{conn: conn} do
      # Create a user with lowercase username
      _user = user_fixture(%{username: "testuser"})

      # Check uppercase version
      conn = get(conn, ~p"/api/username/availability/TESTUSER")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert response["valid"] == true
      assert response["username"] == "TESTUSER"
      assert "This username is already taken" in response["errors"]
    end

    test "generates suggestions when username is taken", %{conn: conn} do
      # Create a user first
      _user = user_fixture(%{username: "popular"})

      conn = get(conn, ~p"/api/username/availability/popular")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert length(response["suggestions"]) > 0

      # Check that suggestions are different from the original
      suggestions = response["suggestions"]
      refute "popular" in suggestions

      # Check that suggestions follow the username format
      Enum.each(suggestions, fn suggestion ->
        assert String.match?(suggestion, ~r/^[a-zA-Z0-9_-]{3,30}$/)
      end)
    end

    test "generates suggestions when username is reserved", %{conn: conn} do
      conn = get(conn, ~p"/api/username/availability/support")

      response = json_response(conn, 200)
      assert response["available"] == false
      assert length(response["suggestions"]) > 0

      # Check that suggestions are different from the reserved word
      suggestions = response["suggestions"]
      refute "support" in suggestions
    end

    test "respects URL encoding in username parameter", %{conn: conn} do
      # Test with a username that contains characters that need URL encoding
      encoded_username = URI.encode("test user")
      conn = get(conn, "/api/username/availability/#{encoded_username}")

      response = json_response(conn, 200)
      assert response["username"] == "test user"
      assert response["valid"] == false

      assert "Username must be 3-30 characters and contain only letters, numbers, underscores, and hyphens" in response[
               "errors"
             ]
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
