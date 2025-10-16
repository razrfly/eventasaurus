defmodule Eventasaurus.SocialCards.UrlBuilderTest do
  use ExUnit.Case, async: true

  alias Eventasaurus.SocialCards.UrlBuilder

  describe "build_path/3 for events" do
    test "generates path with event slug and hash" do
      event = %{
        slug: "tech-meetup",
        title: "Tech Meetup",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = UrlBuilder.build_path(:event, event)

      assert String.starts_with?(path, "/tech-meetup/social-card-")
      assert String.ends_with?(path, ".png")
      assert Regex.match?(~r/\/tech-meetup\/social-card-[a-f0-9]{8}\.png$/, path)
    end

    test "handles events with ID fallback" do
      event = %{
        id: 42,
        title: "Test Event",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = UrlBuilder.build_path(:event, event)

      assert String.starts_with?(path, "/event-42/social-card-")
    end
  end

  describe "build_path/3 for polls" do
    test "generates path with event slug, poll number, and hash" do
      poll = %{
        number: 1,
        title: "Pizza Poll",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event = %{slug: "tech-meetup"}

      path = UrlBuilder.build_path(:poll, poll, event: event)

      assert String.starts_with?(path, "/tech-meetup/polls/1/social-card-")
      assert String.ends_with?(path, ".png")
      assert Regex.match?(~r/\/tech-meetup\/polls\/1\/social-card-[a-f0-9]{8}\.png$/, path)
    end

    test "requires event option for polls" do
      poll = %{number: 1, title: "Pizza Poll"}

      assert_raise KeyError, fn ->
        UrlBuilder.build_path(:poll, poll)
      end
    end
  end

  describe "build_url/3" do
    test "generates complete URL for events" do
      event = %{
        slug: "tech-meetup",
        title: "Tech Meetup",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      url = UrlBuilder.build_url(:event, event)

      assert String.starts_with?(url, "http")
      assert String.contains?(url, "/tech-meetup/social-card-")
      assert String.ends_with?(url, ".png")
    end

    test "generates complete URL for polls" do
      poll = %{number: 1, title: "Pizza Poll", updated_at: ~N[2023-01-01 12:00:00]}
      event = %{slug: "tech-meetup"}

      url = UrlBuilder.build_url(:poll, poll, event: event)

      assert String.starts_with?(url, "http")
      assert String.contains?(url, "/tech-meetup/polls/1/social-card-")
    end
  end

  describe "extract_hash/1" do
    test "extracts hash from event URL" do
      path = "/tech-meetup/social-card-abc12345.png"

      hash = UrlBuilder.extract_hash(path)

      assert hash == "abc12345"
    end

    test "extracts hash from poll URL" do
      path = "/tech-meetup/polls/1/social-card-abc12345.png"

      hash = UrlBuilder.extract_hash(path)

      assert hash == "abc12345"
    end

    test "returns nil for invalid paths" do
      invalid_paths = [
        "/invalid/path",
        "/tech-meetup/wrong-pattern.png",
        "",
        "/tech-meetup/social-card-tooshort.png"
      ]

      for path <- invalid_paths do
        assert UrlBuilder.extract_hash(path) == nil
      end
    end
  end

  describe "detect_entity_type/1" do
    test "detects event type" do
      path = "/tech-meetup/social-card-abc12345.png"

      assert UrlBuilder.detect_entity_type(path) == :event
    end

    test "detects poll type" do
      path = "/tech-meetup/polls/1/social-card-abc12345.png"

      assert UrlBuilder.detect_entity_type(path) == :poll
    end

    test "returns nil for invalid paths" do
      assert UrlBuilder.detect_entity_type("/invalid/path") == nil
      assert UrlBuilder.detect_entity_type("") == nil
    end

    test "prioritizes poll detection over event for ambiguous patterns" do
      # If a path could match both patterns, poll should win (more specific)
      poll_path = "/tech-meetup/polls/1/social-card-abc12345.png"

      assert UrlBuilder.detect_entity_type(poll_path) == :poll
    end
  end

  describe "parse_path/1" do
    test "parses event URL completely" do
      path = "/tech-meetup/social-card-abc12345.png"

      result = UrlBuilder.parse_path(path)

      assert result == %{
               entity_type: :event,
               event_slug: "tech-meetup",
               hash: "abc12345"
             }
    end

    test "parses poll URL completely" do
      path = "/tech-meetup/polls/1/social-card-abc12345.png"

      result = UrlBuilder.parse_path(path)

      assert result == %{
               entity_type: :poll,
               event_slug: "tech-meetup",
               poll_number: 1,
               hash: "abc12345"
             }
    end

    test "handles complex event slugs" do
      path = "/my-awesome-tech-event-2023/social-card-abc12345.png"

      result = UrlBuilder.parse_path(path)

      assert result.event_slug == "my-awesome-tech-event-2023"
      assert result.entity_type == :event
    end

    test "returns nil for invalid paths" do
      assert UrlBuilder.parse_path("/invalid/path") == nil
      assert UrlBuilder.parse_path("") == nil
      assert UrlBuilder.parse_path("/tech-meetup/wrong-pattern.png") == nil
    end
  end

  describe "validate_hash/4" do
    test "validates correct event hash" do
      event = %{
        slug: "tech-meetup",
        title: "Tech Meetup",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = UrlBuilder.build_path(:event, event)
      hash = UrlBuilder.extract_hash(path)

      assert UrlBuilder.validate_hash(:event, event, hash) == true
    end

    test "rejects incorrect event hash" do
      event = %{
        slug: "tech-meetup",
        title: "Tech Meetup",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      assert UrlBuilder.validate_hash(:event, event, "invalid") == false
    end

    test "validates correct poll hash" do
      poll = %{
        number: 1,
        title: "Pizza Poll",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event = %{slug: "tech-meetup"}
      path = UrlBuilder.build_path(:poll, poll, event: event)
      hash = UrlBuilder.extract_hash(path)

      assert UrlBuilder.validate_hash(:poll, poll, hash) == true
    end

    test "rejects incorrect poll hash" do
      poll = %{number: 1, title: "Pizza Poll"}

      assert UrlBuilder.validate_hash(:poll, poll, "invalid") == false
    end

    test "rejects hash when entity data changes" do
      original_event = %{
        slug: "tech-meetup",
        title: "Original Title",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      modified_event = %{original_event | title: "Modified Title"}

      path = UrlBuilder.build_path(:event, original_event)
      hash = UrlBuilder.extract_hash(path)

      assert UrlBuilder.validate_hash(:event, modified_event, hash) == false
    end
  end

  describe "integration tests" do
    test "round-trip: event path generation and parsing" do
      event = %{
        slug: "tech-meetup",
        title: "Tech Meetup",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      # Generate path
      path = UrlBuilder.build_path(:event, event)

      # Parse it back
      parsed = UrlBuilder.parse_path(path)

      assert parsed.entity_type == :event
      assert parsed.event_slug == "tech-meetup"
      assert String.length(parsed.hash) == 8
    end

    test "round-trip: poll path generation and parsing" do
      poll = %{number: 1, title: "Pizza Poll", updated_at: ~N[2023-01-01 12:00:00]}
      event = %{slug: "tech-meetup"}

      # Generate path
      path = UrlBuilder.build_path(:poll, poll, event: event)

      # Parse it back
      parsed = UrlBuilder.parse_path(path)

      assert parsed.entity_type == :poll
      assert parsed.event_slug == "tech-meetup"
      assert parsed.poll_number == 1
      assert String.length(parsed.hash) == 8
    end

    test "different events produce different hashes" do
      event1 = %{slug: "event-1", title: "Event 1", updated_at: ~N[2023-01-01 12:00:00]}
      event2 = %{slug: "event-2", title: "Event 2", updated_at: ~N[2023-01-01 12:00:00]}

      path1 = UrlBuilder.build_path(:event, event1)
      path2 = UrlBuilder.build_path(:event, event2)

      hash1 = UrlBuilder.extract_hash(path1)
      hash2 = UrlBuilder.extract_hash(path2)

      assert hash1 != hash2
    end

    test "same event produces consistent hash" do
      event = %{slug: "tech-meetup", title: "Tech Meetup", updated_at: ~N[2023-01-01 12:00:00]}

      paths = for _ <- 1..5, do: UrlBuilder.build_path(:event, event)
      hashes = Enum.map(paths, &UrlBuilder.extract_hash/1)

      # All hashes should be identical
      assert Enum.uniq(hashes) |> length() == 1
    end
  end
end
