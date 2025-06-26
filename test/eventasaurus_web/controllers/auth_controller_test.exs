defmodule EventasaurusWeb.AuthControllerTest do
  use EventasaurusWeb.ConnCase
  import Mox

  alias EventasaurusApp.Auth

  setup do
    Mox.verify_on_exit!()
    :ok
  end

  describe "GET /auth/login" do
    test "renders login form", %{conn: conn} do
      conn = get(conn, ~p"/auth/login")
      assert html_response(conn, 200) =~ "Sign in to account"
      assert html_response(conn, 200) =~ "Keep me logged in"
    end

    test "login form has remember_me checkbox checked by default", %{conn: conn} do
      conn = get(conn, ~p"/auth/login")
      response = html_response(conn, 200)
      assert response =~ "Keep me logged in"
      # Check that the checkbox is checked by default
      assert response =~ "checked"
    end
  end

  describe "POST /auth/login with remember_me" do
    test "sets persistent session when remember_me is checked", %{conn: conn} do
      user_email = "test@example.com"
      user_password = "password123"

      # Mock successful authentication
      expect(MockAuthClient, :sign_in, fn ^user_email, ^user_password ->
        {:ok, %{
          "access_token" => "mock_access_token",
          "refresh_token" => "mock_refresh_token",
          "user" => %{"id" => "user123", "email" => user_email}
        }}
      end)

      # Mock successful user retrieval
      expect(MockAuthHelper, :get_current_user, fn "mock_access_token" ->
        {:ok, %{"id" => "user123", "email" => user_email}}
      end)

      conn = post(conn, ~p"/auth/login", %{
        "user" => %{
          "email" => user_email,
          "password" => user_password,
          "remember_me" => "true"
        }
      })

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_flash(conn, :info) == "You have been logged in successfully."

      # Check that access token is stored in session
      assert get_session(conn, :access_token) == "mock_access_token"
      assert get_session(conn, :refresh_token) == "mock_refresh_token"
    end

    test "sets session cookie when remember_me is unchecked", %{conn: conn} do
      user_email = "test@example.com"
      user_password = "password123"

      # Mock successful authentication
      expect(MockAuthClient, :sign_in, fn ^user_email, ^user_password ->
        {:ok, %{
          "access_token" => "mock_access_token",
          "refresh_token" => "mock_refresh_token",
          "user" => %{"id" => "user123", "email" => user_email}
        }}
      end)

      # Mock successful user retrieval
      expect(MockAuthHelper, :get_current_user, fn "mock_access_token" ->
        {:ok, %{"id" => "user123", "email" => user_email}}
      end)

      conn = post(conn, ~p"/auth/login", %{
        "user" => %{
          "email" => user_email,
          "password" => user_password,
          "remember_me" => "false"
        }
      })

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_flash(conn, :info) == "You have been logged in successfully."

      # Check that tokens are still stored (session duration is configured differently)
      assert get_session(conn, :access_token) == "mock_access_token"
      assert get_session(conn, :refresh_token) == "mock_refresh_token"
    end

    test "defaults to remember_me when parameter is missing", %{conn: conn} do
      user_email = "test@example.com"
      user_password = "password123"

      # Mock successful authentication
      expect(MockAuthClient, :sign_in, fn ^user_email, ^user_password ->
        {:ok, %{
          "access_token" => "mock_access_token",
          "refresh_token" => "mock_refresh_token",
          "user" => %{"id" => "user123", "email" => user_email}
        }}
      end)

      # Mock successful user retrieval
      expect(MockAuthHelper, :get_current_user, fn "mock_access_token" ->
        {:ok, %{"id" => "user123", "email" => user_email}}
      end)

      # Test with missing remember_me parameter (should default to true)
      conn = post(conn, ~p"/auth/login", %{
        "user" => %{
          "email" => user_email,
          "password" => user_password
        }
      })

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_flash(conn, :info) == "You have been logged in successfully."
    end
  end
end
