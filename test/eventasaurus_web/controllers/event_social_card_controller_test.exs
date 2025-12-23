defmodule EventasaurusWeb.EventSocialCardControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  alias Eventasaurus.SocialCards.{HashGenerator, UrlBuilder}
  alias EventasaurusApp.Events

  describe "GET /slug/social-card-:hash.png" do
    setup do
      # Create a test event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event for Social Card",
          slug: "test-social-card-event",
          description: "Testing social card generation",
          start_at: DateTime.utc_now() |> DateTime.add(7, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
          timezone: "America/New_York",
          theme: :minimal,
          created_by: "test_user_id"
        })

      %{event: event}
    end

    test "returns PNG image for valid event and hash", %{conn: conn, event: event} do
      # Generate correct hash for event
      hash = HashGenerator.generate_hash(event)

      # Make request
      conn = get(conn, "/#{event.slug}/social-card-#{hash}.png")

      # Assert response
      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "image/png")
      [cache_control] = get_resp_header(conn, "cache-control")
      assert String.contains?(cache_control, "public")
      assert String.contains?(cache_control, "max-age=31536000")

      # Verify it's actually PNG data
      png_data = response(conn, 200)
      assert byte_size(png_data) > 0
      # PNG files start with magic bytes: 89 50 4E 47
      assert binary_part(png_data, 0, 4) == <<0x89, 0x50, 0x4E, 0x47>>
    end

    test "returns 404 for non-existent event slug", %{conn: conn} do
      conn = get(conn, "/non-existent-event/social-card-abc12345.png")

      assert conn.status == 404
      assert response(conn, 404) =~ "Event not found"
    end

    test "redirects permanently (301) when hash is outdated", %{conn: conn, event: event} do
      # Use an incorrect/old hash
      old_hash = "outdated1"

      conn = get(conn, "/#{event.slug}/social-card-#{old_hash}.png")

      # Should redirect with 301 to new URL with correct hash
      assert redirected_to(conn, 301) =~ "/#{event.slug}/social-card-"
    end

    test "URL matches UrlBuilder pattern", %{event: event} do
      # Get URL from UrlBuilder
      path = UrlBuilder.build_path(:event, event)

      # Extract components
      assert %{
               entity_type: :event,
               event_slug: event_slug,
               hash: hash
             } = UrlBuilder.parse_path(path)

      assert event_slug == event.slug
      assert hash == HashGenerator.generate_hash(event)
    end

    test "hash changes when event content changes", %{conn: conn, event: event} do
      # Get initial hash
      initial_hash = HashGenerator.generate_hash(event)
      initial_path = "/#{event.slug}/social-card-#{initial_hash}.png"

      # Initial request should succeed
      conn1 = get(conn, initial_path)
      assert conn1.status == 200

      # Update event title (triggers hash change)
      {:ok, updated_event} =
        Events.update_event(event, %{title: "Updated Title for Cache Test"})

      # New hash should be different
      new_hash = HashGenerator.generate_hash(updated_event)
      assert new_hash != initial_hash

      # Old hash should now redirect
      conn2 = get(conn, initial_path)
      assert conn2.status == 301

      # New hash should work
      new_path = "/#{event.slug}/social-card-#{new_hash}.png"
      conn3 = get(conn, new_path)
      assert conn3.status == 200
    end

    test "handles events with special characters in slug", %{conn: conn} do
      {:ok, event} =
        Events.create_event(%{
          title: "Event with Dashes",
          slug: "my-awesome-event-2024",
          description: "Testing slug handling",
          start_at: DateTime.utc_now() |> DateTime.add(7, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
          timezone: "America/New_York",
          theme: :minimal,
          created_by: "test_user_id"
        })

      hash = HashGenerator.generate_hash(event)
      conn = get(conn, "/#{event.slug}/social-card-#{hash}.png")

      assert conn.status == 200
    end

    test "cache headers set correctly for immutable content", %{conn: conn, event: event} do
      hash = HashGenerator.generate_hash(event)
      conn = get(conn, "/#{event.slug}/social-card-#{hash}.png")

      [cache_control] = get_resp_header(conn, "cache-control")
      assert String.contains?(cache_control, "public")
      assert String.contains?(cache_control, "max-age=31536000")
    end

    test "validates hash format (8 hex characters)", %{conn: conn, event: event} do
      # Valid hash format (8 hex chars)
      valid_hash = "abcd1234"
      conn1 = get(conn, "/#{event.slug}/social-card-#{valid_hash}.png")
      # Should either return 200 or 301 (depending on hash match), not 404
      assert conn1.status in [200, 301]

      # Invalid hash format (too short)
      conn2 = get(conn, "/#{event.slug}/social-card-abc.png")
      # Router might not match this pattern at all
      assert conn2.status in [404, 301]
    end
  end

  describe "UrlBuilder integration" do
    test "build_path generates valid route" do
      event = %{
        slug: "test-event",
        title: "Test Event",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = UrlBuilder.build_path(:event, event)

      # Verify pattern matches router expectation
      assert path =~ ~r/^\/test-event\/social-card-[a-f0-9]{8}\.png$/
    end

    test "extract_hash works with generated URLs" do
      event = %{
        slug: "test-event",
        title: "Test Event",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = UrlBuilder.build_path(:event, event)
      hash = UrlBuilder.extract_hash(path)

      assert hash == HashGenerator.generate_hash(event)
    end

    test "validate_hash correctly identifies valid and invalid hashes" do
      event = %{
        slug: "test-event",
        title: "Test Event",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      valid_hash = HashGenerator.generate_hash(event)
      assert UrlBuilder.validate_hash(:event, event, valid_hash) == true

      invalid_hash = "invalid1"
      assert UrlBuilder.validate_hash(:event, event, invalid_hash) == false
    end
  end
end
