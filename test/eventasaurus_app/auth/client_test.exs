defmodule EventasaurusApp.Auth.ClientTest do
  @moduledoc """
  Comprehensive tests for authentication client covering both regular signup
  and event registration flows with the new passwordless OTP implementation.
  """

  use EventasaurusApp.DataCase, async: true
  alias EventasaurusApp.Auth.Client
  import Mox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "sign_in_with_otp/2 - Event Registration Flow" do
    test "successful OTP request for new user" do
      EventasaurusApp.HTTPoison.Mock
      |> expect(:post, fn url, body, headers ->
        assert String.ends_with?(url, "/auth/v1/otp")

        parsed_body = Jason.decode!(body)
        assert parsed_body["email"] == "eventuser@example.com"
        assert parsed_body["options"]["shouldCreateUser"] == true
        assert parsed_body["data"]["name"] == "Event User"
        assert parsed_body["options"]["emailRedirectTo"] != nil

        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{
            "email_sent" => true,
            "email" => "eventuser@example.com",
            "message_id" => "otp-message-12345"
          })
        }}
      end)

      user_metadata = %{name: "Event User"}
      result = Client.sign_in_with_otp("eventuser@example.com", user_metadata)

      assert {:ok, response} = result
      assert response["email_sent"] == true
      assert response["email"] == "eventuser@example.com"
      assert response["message_id"] == "otp-message-12345"
    end

    test "handles invalid email format" do
      EventasaurusApp.HTTPoison.Mock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 422,
          body: Jason.encode!(%{
            "msg" => "Invalid email format",
            "error_description" => "Please provide a valid email address"
          })
        }}
      end)

      result = Client.sign_in_with_otp("invalid-email", %{name: "Test User"})

      assert {:error, %{status: 422, message: "OTP request failed"}} = result
    end
  end

  describe "admin_get_user_by_email/1 - User Lookup" do
    test "finds existing user" do
      EventasaurusApp.HTTPoison.Mock
      |> expect(:get, fn url, headers ->
        assert String.contains?(url, "/auth/v1/admin/users")
        # Note: admin API fetches all users and filters manually, no email param in URL

        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{
            "users" => [%{
              "id" => "uuid-existing-user",
              "email" => "existing@example.com",
              "email_confirmed_at" => "2024-01-15T10:30:00.000Z",
              "user_metadata" => %{"name" => "Existing User"}
            }],
            "total" => 1
          })
        }}
      end)

      result = Client.admin_get_user_by_email("existing@example.com")

      assert {:ok, user} = result
      assert user["email"] == "existing@example.com"
      assert user["email_confirmed_at"] != nil
    end

    test "returns nil for non-existent user" do
      EventasaurusApp.HTTPoison.Mock
      |> expect(:get, fn _url, _headers ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{
            "users" => [],
            "total" => 0
          })
        }}
      end)

      result = Client.admin_get_user_by_email("nonexistent@example.com")

      assert {:ok, nil} = result
    end
  end
end
