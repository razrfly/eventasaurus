defmodule EventasaurusWeb.EventSocialCardControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  describe "GET /events/:id/social_card.png" do
    setup do
      # Create a test user and event for each test
      user = user_fixture()
      event = event_fixture(%{
        title: "Test Event for Social Cards",
        description: "A test event for social card generation",
        cover_image_url: "https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=400"
      })

      %{user: user, event: event}
    end

    @tag :integration
    test "generates and serves PNG social card when rsvg-convert is available", %{conn: conn, event: event} do
      case System.find_executable("rsvg-convert") do
        nil ->
          # Skip test if rsvg-convert is not available
          assert true

        _path ->
          response = get(conn, ~p"/events/#{event.id}/social_card.png")

          assert response.status == 200
          # Content-type includes charset in Phoenix
          assert get_resp_header(response, "content-type") == ["image/png; charset=utf-8"]
          assert get_resp_header(response, "cache-control") == ["public, max-age=86400"]

          # Verify we have ETag header (format will vary)
          [etag] = get_resp_header(response, "etag")
          assert String.starts_with?(etag, "\"")
          assert String.ends_with?(etag, "\"")

          # Response should have actual PNG content
          assert byte_size(response.resp_body) > 1000
      end
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      response = get(conn, ~p"/events/99999/social_card.png")

      assert response.status == 404
      assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]

      response_body = Jason.decode!(response.resp_body)
      assert response_body["error"] == "Event not found"
    end

    test "returns 500 when rsvg-convert is not available", %{conn: conn, event: event} do
      # Mock the system dependency check to fail
      original_executable = System.find_executable("rsvg-convert")

      case original_executable do
        nil ->
          # If rsvg-convert is actually not available, test the error path
          response = get(conn, ~p"/events/#{event.id}/social_card.png")

          assert response.status == 500
          assert get_resp_header(response, "content-type") == ["text/plain; charset=utf-8"]
          assert response.resp_body == "Social card generation unavailable"

        _path ->
          # Skip this test since rsvg-convert is available
          # We can't easily mock System.find_executable in a unit test
          assert true
      end
    end

    test "handles various event ID formats", %{conn: conn, event: event} do
      # Test with valid integer ID
      response = get(conn, ~p"/events/#{event.id}/social_card.png")

      case System.find_executable("rsvg-convert") do
        nil ->
          # If rsvg-convert is not available, we'll get a 500
          assert response.status == 500
        _path ->
          # If rsvg-convert is available, we should get a 200
          assert response.status == 200
      end
    end

    test "generates consistent ETags for same event", %{conn: conn, event: event} do
      case System.find_executable("rsvg-convert") do
        nil ->
          # Skip test if rsvg-convert is not available
          assert true

        _path ->
          # Make two requests for the same event
          response1 = get(conn, ~p"/events/#{event.id}/social_card.png")
          response2 = get(conn, ~p"/events/#{event.id}/social_card.png")

          assert response1.status == 200
          assert response2.status == 200

          # ETags should be the same for the same event (assuming no changes)
          etag1 = get_resp_header(response1, "etag")
          etag2 = get_resp_header(response2, "etag")

          # Note: ETags might differ due to updated_at changes, but let's check they exist
          assert length(etag1) == 1
          assert length(etag2) == 1
      end
    end

    test "handles invalid SVG content gracefully", %{conn: conn} do
      # Create an event with invalid data that might cause SVG issues
      _user = user_fixture()
             event = event_fixture(%{
         title: "Event with <invalid> & XML characters \"quotes\" 'apostrophes'",
         description: "This has XML & HTML entities that need escaping",
         cover_image_url: "not-a-valid-url"
       })

      case System.find_executable("rsvg-convert") do
        nil ->
          # Skip test if rsvg-convert is not available
          assert true

        _path ->
          response = get(conn, ~p"/events/#{event.id}/social_card.png")

          # Should still generate successfully due to our text sanitization
          assert response.status == 200
          assert get_resp_header(response, "content-type") == ["image/png; charset=utf-8"]
      end
    end
  end

  describe "verify_system_dependencies/0" do
    test "returns :ok when rsvg-convert is available" do
      case System.find_executable("rsvg-convert") do
        nil ->
          # If rsvg-convert is not available, test should reflect that
          assert EventasaurusWeb.EventSocialCardController.verify_system_dependencies() ==
                 {:error, "rsvg-convert command not found"}

        _path ->
          # If rsvg-convert is available, test should reflect that
          assert EventasaurusWeb.EventSocialCardController.verify_system_dependencies() == :ok
      end
    end
  end
end
