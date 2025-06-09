defmodule EventasaurusWeb.EventSocialCardControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias Eventasaurus.SocialCards.HashGenerator

  describe "GET /events/:slug/social-card-:hash.png" do
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
          hash = HashGenerator.generate_hash(event)
          response = get(conn, "/events/#{event.slug}/social-card-#{hash}.png")

          assert response.status == 200
          # Content-type includes charset in Phoenix
          assert get_resp_header(response, "content-type") == ["image/png; charset=utf-8"]
          assert get_resp_header(response, "cache-control") == ["public, max-age=31536000"]  # 1 year cache

          # Verify we have ETag header (format will vary)
          [etag] = get_resp_header(response, "etag")
          assert String.starts_with?(etag, "\"")
          assert String.ends_with?(etag, "\"")

          # Response should have actual PNG content
          assert byte_size(response.resp_body) > 1000
      end
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      response = get(conn, "/events/non-existent-slug/social-card-abcd1234.png")

      assert response.status == 404
      assert response.resp_body == "Event not found"
    end

    test "returns 301 redirect for stale hash", %{conn: conn, event: event} do
      # Use an incorrect hash
      stale_hash = "stale123"
      response = get(conn, "/events/#{event.slug}/social-card-#{stale_hash}.png")

      assert response.status == 301

      # Should redirect to current URL with correct hash
      [location] = get_resp_header(response, "location")
      current_hash = HashGenerator.generate_hash(event)
      assert location == "/events/#{event.slug}/social-card-#{current_hash}.png"
    end

    test "handles various hash formats", %{conn: conn, event: event} do
      # Test with valid hash
      hash = HashGenerator.generate_hash(event)
      response = get(conn, "/events/#{event.slug}/social-card-#{hash}.png")

      case System.find_executable("rsvg-convert") do
        nil ->
          # If rsvg-convert is not available, we'll get a 500
          assert response.status == 500
        _path ->
          # If rsvg-convert is available, we should get a 200
          assert response.status == 200
      end
    end

    test "generates consistent hashes for same event", %{conn: conn, event: event} do
      # Generate hash twice for the same event
      hash1 = HashGenerator.generate_hash(event)
      hash2 = HashGenerator.generate_hash(event)

      # Hashes should be identical for the same event data
      assert hash1 == hash2

      case System.find_executable("rsvg-convert") do
        nil ->
          # Skip test if rsvg-convert is not available
          assert true

        _path ->
          # Make two requests with the same hash
          response1 = get(conn, "/events/#{event.slug}/social-card-#{hash1}.png")
          response2 = get(conn, "/events/#{event.slug}/social-card-#{hash2}.png")

          assert response1.status == 200
          assert response2.status == 200

          # ETags should be the same since hash is the same
          etag1 = get_resp_header(response1, "etag")
          etag2 = get_resp_header(response2, "etag")

          assert etag1 == etag2
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
          hash = HashGenerator.generate_hash(event)
          response = get(conn, "/events/#{event.slug}/social-card-#{hash}.png")

          # Should still generate successfully due to our text sanitization
          assert response.status == 200
          assert get_resp_header(response, "content-type") == ["image/png; charset=utf-8"]
      end
    end

    test "hash changes when event data changes", %{conn: _conn, event: event} do
      # Generate initial hash
      initial_hash = HashGenerator.generate_hash(event)

      # Update the event (simulate a change)
      updated_event = %{event | title: "Updated Event Title", updated_at: DateTime.utc_now()}
      new_hash = HashGenerator.generate_hash(updated_event)

      # Hashes should be different
      assert initial_hash != new_hash
    end
  end


end
