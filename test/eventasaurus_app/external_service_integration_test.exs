defmodule EventasaurusApp.ExternalServiceIntegrationTest do
  @moduledoc """
  Integration tests demonstrating how to use Mox for testing modules that depend on external services.
  Part of Task 7: Set up Mox for external service mocking.

  This serves as an example of how to write tests that mock external dependencies
  while testing internal business logic.
  """

  use ExUnit.Case, async: true
  import Mox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "Authentication flow with mocked auth service" do
    test "successful user authentication" do
      # Arrange: Mock the Auth.Client to return successful authentication
      EventasaurusApp.Auth.ClientMock
      |> expect(:sign_in, fn "user@example.com", "password123" ->
        {:ok, %{
          "access_token" => "mocked_access_token_12345",
          "refresh_token" => "mocked_refresh_token_67890",
          "user" => %{
            "id" => "user-uuid-12345",
            "email" => "user@example.com",
            "user_metadata" => %{"name" => "John Doe"}
          }
        }}
      end)

      # Act: Simulate calling our authentication logic
      # (In a real test, this would be calling our actual authentication module)
      auth_result = EventasaurusApp.Auth.ClientMock.sign_in("user@example.com", "password123")

      # Assert: Verify the authentication was successful
      assert {:ok, auth_data} = auth_result
      assert auth_data["access_token"] == "mocked_access_token_12345"
      assert auth_data["user"]["email"] == "user@example.com"
      assert auth_data["user"]["user_metadata"]["name"] == "John Doe"
    end

    test "failed authentication with invalid credentials" do
      # Arrange: Mock the Auth.Client to return authentication failure
      EventasaurusApp.Auth.ClientMock
      |> expect(:sign_in, fn "user@example.com", "wrong_password" ->
        {:error, %{status: 401, message: "Invalid credentials"}}
      end)

      # Act: Simulate authentication with wrong password
      auth_result = EventasaurusApp.Auth.ClientMock.sign_in("user@example.com", "wrong_password")

      # Assert: Verify the authentication failed as expected
      assert {:error, error_data} = auth_result
      assert error_data.status == 401
      assert error_data.message == "Invalid credentials"
    end
  end

  describe "Image search functionality with mocked Unsplash" do
    test "successful photo search returns formatted results" do
      # Arrange: Mock Unsplash API to return search results
      EventasaurusWeb.Services.UnsplashServiceMock
      |> expect(:search_photos, fn "conference", 1, 12 ->
        {:ok, [
          %{
            id: "unsplash-photo-1",
            description: "Professional conference room",
            urls: %{
              regular: "https://images.unsplash.com/photo-1.jpg",
              thumb: "https://images.unsplash.com/photo-1-thumb.jpg"
            },
            user: %{name: "Conference Photographer"},
            download_location: "https://api.unsplash.com/photos/photo-1/download"
          },
          %{
            id: "unsplash-photo-2",
            description: "Business meeting setup",
            urls: %{
              regular: "https://images.unsplash.com/photo-2.jpg",
              thumb: "https://images.unsplash.com/photo-2-thumb.jpg"
            },
            user: %{name: "Event Photographer"},
            download_location: "https://api.unsplash.com/photos/photo-2/download"
          }
        ]}
      end)

      # Act: Search for conference photos
      search_result = EventasaurusWeb.Services.UnsplashServiceMock.search_photos("conference", 1, 12)

      # Assert: Verify the search returned properly formatted results
      assert {:ok, photos} = search_result
      assert length(photos) == 2

      [first_photo, second_photo] = photos
      assert first_photo.id == "unsplash-photo-1"
      assert first_photo.description == "Professional conference room"
      assert first_photo.user.name == "Conference Photographer"

      assert second_photo.id == "unsplash-photo-2"
      assert second_photo.description == "Business meeting setup"
    end

    test "empty search query returns error" do
      # Arrange: Mock Unsplash API to return error for empty query
      EventasaurusWeb.Services.UnsplashServiceMock
      |> expect(:search_photos, fn "", _, _ ->
        {:error, "Search query cannot be empty"}
      end)

      # Act: Search with empty query
      search_result = EventasaurusWeb.Services.UnsplashServiceMock.search_photos("", 1, 12)

      # Assert: Verify the error is returned
      assert {:error, "Search query cannot be empty"} = search_result
    end
  end

  describe "Movie/media search with mocked TMDb" do
    test "successful media search returns mixed results" do
      # Arrange: Mock TMDb API to return mixed search results
      EventasaurusWeb.Services.TmdbServiceMock
      |> expect(:search_multi, fn "Marvel", 1 ->
        {:ok, [
          %{
            type: :movie,
            id: 299534,
            title: "Avengers: Endgame",
            overview: "The final battle for the fate of Earth...",
            poster_path: "/or06FN3Dka5tukK1e9sl16pB3iy.jpg",
            release_date: "2019-04-24"
          },
          %{
            type: :tv,
            id: 1403,
            name: "Marvel's Agents of S.H.I.E.L.D.",
            overview: "Agent Phil Coulson of S.H.I.E.L.D...",
            poster_path: "/gHUCCMy1vvj58tzE3dZqeC9SXus.jpg",
            first_air_date: "2013-09-24"
          },
          %{
            type: :person,
            id: 3223,
            name: "Robert Downey Jr.",
            known_for_department: "Acting",
            profile_path: "/5qHNjhtjMD4YWH3UP0rm4tKwxCL.jpg"
          }
        ]}
      end)

      # Act: Search for Marvel content
      search_result = EventasaurusWeb.Services.TmdbServiceMock.search_multi("Marvel", 1)

      # Assert: Verify mixed results are returned correctly
      assert {:ok, results} = search_result
      assert length(results) == 3

      # Check movie result
      movie = Enum.find(results, &(&1.type == :movie))
      assert movie.title == "Avengers: Endgame"
      assert movie.id == 299534

      # Check TV show result
      tv_show = Enum.find(results, &(&1.type == :tv))
      assert tv_show.name == "Marvel's Agents of S.H.I.E.L.D."
      assert tv_show.id == 1403

      # Check person result
      person = Enum.find(results, &(&1.type == :person))
      assert person.name == "Robert Downey Jr."
      assert person.known_for_department == "Acting"
    end
  end

  describe "Mox configuration and best practices demonstration" do
    test "demonstrates stub vs expect usage" do
      # Using stub() for a function that might be called multiple times
      EventasaurusApp.Auth.ClientMock
      |> stub(:get_user, fn _token ->
        {:ok, %{"id" => "stub-user", "email" => "stub@example.com"}}
      end)

      # Using expect() for a function that should be called exactly once
      EventasaurusApp.Auth.ClientMock
      |> expect(:refresh_token, 1, fn "old_refresh_token" ->
        {:ok, %{"access_token" => "new_access_token", "refresh_token" => "new_refresh_token"}}
      end)

      # Act: Call the stubbed function multiple times (allowed)
      result1 = EventasaurusApp.Auth.ClientMock.get_user("token1")
      result2 = EventasaurusApp.Auth.ClientMock.get_user("token2")

      # Call the expected function exactly once (required)
      refresh_result = EventasaurusApp.Auth.ClientMock.refresh_token("old_refresh_token")

      # Assert: All calls worked as expected
      assert {:ok, _user1} = result1
      assert {:ok, _user2} = result2
      assert {:ok, tokens} = refresh_result
      assert tokens["access_token"] == "new_access_token"
    end

    test "demonstrates how to mock HTTP client directly" do
      # This test shows how we could mock HTTPoison.Base if needed
      EventasaurusApp.HTTPoison.Mock
      |> expect(:get, fn "https://api.example.com/data", _headers, _options ->
        {:ok, %HTTPoison.Response{
          status_code: 200,
          body: Jason.encode!(%{"data" => "mocked response"}),
          headers: [{"content-type", "application/json"}]
        }}
      end)

      # Act: Call the mocked HTTP client
      response = EventasaurusApp.HTTPoison.Mock.get("https://api.example.com/data", [], [])

      # Assert: Verify the mocked response
      assert {:ok, %HTTPoison.Response{status_code: 200, body: body}} = response
      assert Jason.decode!(body) == %{"data" => "mocked response"}
    end
  end
end
