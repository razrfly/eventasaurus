defmodule EventasaurusApp.MoxSetupTest do
  @moduledoc """
  Test to verify that Mox is correctly set up and can mock external services.
  Part of Task 7: Set up Mox for external service mocking.
  """

  use ExUnit.Case, async: true
  import Mox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "Mox setup verification" do
    test "can mock Auth.Client behaviour" do
      # Arrange: Set up mock expectations
      EventasaurusApp.Auth.ClientMock
      |> expect(:get_user, fn "test_token" ->
        {:ok, %{
          "id" => "test-user-id",
          "email" => "test@example.com",
          "user_metadata" => %{"name" => "Test User"}
        }}
      end)

      # Act: Call the mock
      result = EventasaurusApp.Auth.ClientMock.get_user("test_token")

      # Assert: Verify the mock returned expected data
      assert {:ok, user_data} = result
      assert user_data["email"] == "test@example.com"
      assert user_data["user_metadata"]["name"] == "Test User"
    end

    test "can mock UnsplashService behaviour" do
      # Arrange: Set up mock expectations for photo search
      EventasaurusWeb.Services.UnsplashServiceMock
      |> expect(:search_photos, fn "nature", 1, 10 ->
        {:ok, [
          %{
            id: "photo-1",
            description: "Beautiful nature photo",
            urls: %{regular: "https://example.com/photo1.jpg"},
            user: %{name: "Test Photographer"},
            download_location: "https://api.unsplash.com/photos/photo-1/download"
          }
        ]}
      end)

      # Act: Call the mock
      result = EventasaurusWeb.Services.UnsplashServiceMock.search_photos("nature", 1, 10)

      # Assert: Verify the mock returned expected data
      assert {:ok, photos} = result
      assert length(photos) == 1
      assert List.first(photos).id == "photo-1"
      assert List.first(photos).description == "Beautiful nature photo"
    end

    test "can mock TmdbService behaviour" do
      # Arrange: Set up mock expectations for movie search
      EventasaurusWeb.Services.TmdbServiceMock
      |> expect(:search_multi, fn "Avatar", 1 ->
        {:ok, [
          %{
            type: :movie,
            id: 19995,
            title: "Avatar",
            overview: "A paraplegic Marine dispatched to the moon Pandora...",
            poster_path: "/jRXYjXNq0Cs2TcJjLkki24MLp7u.jpg"
          }
        ]}
      end)

      # Act: Call the mock
      result = EventasaurusWeb.Services.TmdbServiceMock.search_multi("Avatar", 1)

      # Assert: Verify the mock returned expected data
      assert {:ok, results} = result
      assert length(results) == 1
      assert List.first(results).type == :movie
      assert List.first(results).title == "Avatar"
    end

    test "mocks are isolated between tests" do
      # This test verifies that mocks don't leak between tests
      # Each test should start with a clean slate

      # Arrange: Set up a different mock expectation
      EventasaurusApp.Auth.ClientMock
      |> expect(:sign_in, fn "user@test.com", "password123" ->
        {:ok, %{
          "access_token" => "mock_access_token",
          "refresh_token" => "mock_refresh_token"
        }}
      end)

      # Act: Call the mock
      result = EventasaurusApp.Auth.ClientMock.sign_in("user@test.com", "password123")

      # Assert: Verify the mock worked correctly
      assert {:ok, auth_data} = result
      assert auth_data["access_token"] == "mock_access_token"
      assert auth_data["refresh_token"] == "mock_refresh_token"
    end

    test "can mock error scenarios" do
      # Arrange: Set up mock to return an error
      EventasaurusWeb.Services.UnsplashServiceMock
      |> expect(:search_photos, fn "", _, _ ->
        {:error, "Search query cannot be empty"}
      end)

      # Act: Call the mock with invalid input
      result = EventasaurusWeb.Services.UnsplashServiceMock.search_photos("", 1, 10)

      # Assert: Verify the mock returned the expected error
      assert {:error, "Search query cannot be empty"} = result
    end
  end
end
