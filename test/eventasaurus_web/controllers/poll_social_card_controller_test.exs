defmodule EventasaurusWeb.PollSocialCardControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  import EventasaurusApp.AccountsFixtures

  alias Eventasaurus.SocialCards.{PollHashGenerator, UrlBuilder}
  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo

  describe "GET /:event_slug/polls/:poll_number/social-card-:hash.png" do
    setup do
      # Create a user for poll ownership
      user = user_fixture()

      # Create a test event
      {:ok, event} =
        Events.create_event(%{
          title: "Test Event for Poll Social Card",
          slug: "test-poll-event",
          description: "Testing poll social card generation",
          start_at: DateTime.utc_now() |> DateTime.add(7, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(2, :hour),
          timezone: "America/New_York",
          theme: :minimal,
          created_by: "test_user_id"
        })

      # Create a test poll
      {:ok, poll} =
        Events.create_poll(%{
          event_id: event.id,
          title: "Test Poll",
          poll_type: "general",
          voting_system: "binary",
          phase: "voting",
          created_by_id: user.id
        })

      # Add some poll options
      {:ok, _option1} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Option 1",
          status: "active",
          suggested_by_id: user.id
        })

      {:ok, _option2} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Option 2",
          status: "active",
          suggested_by_id: user.id
        })

      # Reload poll with options
      poll = Events.get_poll!(poll.id) |> Repo.preload([:poll_options, :event])

      %{event: event, poll: poll}
    end

    test "returns PNG image for valid poll and hash", %{conn: conn, event: event, poll: poll} do
      # Generate correct hash for poll
      hash = PollHashGenerator.generate_hash(poll)

      # Make request
      conn = get(conn, "/#{event.slug}/polls/#{poll.number}/social-card-#{hash}.png")

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

    test "returns 404 for non-existent event slug", %{conn: conn, poll: poll} do
      hash = PollHashGenerator.generate_hash(poll)
      conn = get(conn, "/non-existent-event/polls/#{poll.number}/social-card-#{hash}.png")

      assert conn.status == 404
      assert response(conn, 404) =~ "Event not found"
    end

    test "returns 404 for non-existent poll number", %{conn: conn, event: event} do
      conn = get(conn, "/#{event.slug}/polls/999/social-card-abc12345.png")

      assert conn.status == 404
      assert response(conn, 404) =~ "Poll not found"
    end

    test "redirects permanently (301) when hash is outdated", %{
      conn: conn,
      event: event,
      poll: poll
    } do
      # Use an incorrect/old hash
      old_hash = "outdated1"

      conn = get(conn, "/#{event.slug}/polls/#{poll.number}/social-card-#{old_hash}.png")

      # Should redirect with 301 to new URL with correct hash
      assert redirected_to(conn, 301) =~ "/#{event.slug}/polls/#{poll.number}/social-card-"
    end

    test "URL matches UrlBuilder pattern", %{event: event, poll: poll} do
      # Get URL from UrlBuilder
      path = UrlBuilder.build_path(:poll, poll, event: event)

      # Extract components
      assert %{
               entity_type: :poll,
               event_slug: event_slug,
               poll_number: poll_number,
               hash: hash
             } = UrlBuilder.parse_path(path)

      assert event_slug == event.slug
      assert poll_number == poll.number
      assert hash == PollHashGenerator.generate_hash(poll)
    end

    test "hash changes when poll content changes", %{conn: conn, event: event, poll: poll} do
      # Get initial hash
      initial_hash = PollHashGenerator.generate_hash(poll)
      initial_path = "/#{event.slug}/polls/#{poll.number}/social-card-#{initial_hash}.png"

      # Initial request should succeed
      conn1 = get(conn, initial_path)
      assert conn1.status == 200

      # Update poll title (triggers hash change)
      {:ok, updated_poll} = Events.update_poll(poll, %{title: "Updated Poll Title"})

      # New hash should be different
      new_hash = PollHashGenerator.generate_hash(updated_poll)
      assert new_hash != initial_hash

      # Old hash should now redirect
      conn2 = get(conn, initial_path)
      assert conn2.status == 301

      # New hash should work
      new_path = "/#{event.slug}/polls/#{poll.number}/social-card-#{new_hash}.png"
      conn3 = get(conn, new_path)
      assert conn3.status == 200
    end

    test "cache headers set correctly for immutable content", %{
      conn: conn,
      event: event,
      poll: poll
    } do
      hash = PollHashGenerator.generate_hash(poll)
      conn = get(conn, "/#{event.slug}/polls/#{poll.number}/social-card-#{hash}.png")

      [cache_control] = get_resp_header(conn, "cache-control")
      assert String.contains?(cache_control, "public")
      assert String.contains?(cache_control, "max-age=31536000")
    end

    test "validates hash format (8 hex characters)", %{conn: conn, event: event, poll: poll} do
      # Valid hash format (8 hex chars)
      valid_hash = "abcd1234"
      conn1 = get(conn, "/#{event.slug}/polls/#{poll.number}/social-card-#{valid_hash}.png")
      # Should either return 200 or 301 (depending on hash match), not 404
      assert conn1.status in [200, 301]

      # Invalid hash format (too short)
      conn2 = get(conn, "/#{event.slug}/polls/#{poll.number}/social-card-abc.png")
      # Router might not match this pattern at all
      assert conn2.status in [404, 301]
    end
  end

  describe "UrlBuilder integration" do
    test "build_path generates valid route for polls" do
      poll = %{
        number: 1,
        title: "Test Poll",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event = %{slug: "test-event"}

      path = UrlBuilder.build_path(:poll, poll, event: event)

      # Verify pattern matches router expectation
      assert path =~ ~r/^\/test-event\/polls\/1\/social-card-[a-f0-9]{8}\.png$/
    end

    test "extract_hash works with poll URLs" do
      poll = %{
        number: 1,
        title: "Test Poll",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event = %{slug: "test-event"}

      path = UrlBuilder.build_path(:poll, poll, event: event)
      hash = UrlBuilder.extract_hash(path)

      assert hash == PollHashGenerator.generate_hash(poll)
    end

    test "validate_hash correctly identifies valid and invalid hashes for polls" do
      poll = %{
        number: 1,
        title: "Test Poll",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      valid_hash = PollHashGenerator.generate_hash(poll)
      assert UrlBuilder.validate_hash(:poll, poll, valid_hash) == true

      invalid_hash = "invalid1"
      assert UrlBuilder.validate_hash(:poll, poll, invalid_hash) == false
    end
  end
end
