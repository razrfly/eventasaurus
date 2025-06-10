defmodule Eventasaurus.SocialCards.HashGeneratorTest do
  use ExUnit.Case, async: true

  alias Eventasaurus.SocialCards.HashGenerator

  describe "generate_hash/1" do
    test "generates consistent hash for same event data" do
      event = %{
        title: "Test Event",
        description: "A test event",
        cover_image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash1 = HashGenerator.generate_hash(event)
      hash2 = HashGenerator.generate_hash(event)

      assert hash1 == hash2
      assert String.length(hash1) == 8
      assert Regex.match?(~r/^[a-f0-9]{8}$/, hash1)
    end

    test "generates different hashes for different titles" do
      base_event = %{
        slug: "my-event",
        title: "Original Title",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      modified_event = %{base_event | title: "Modified Title"}

      hash1 = HashGenerator.generate_hash(base_event)
      hash2 = HashGenerator.generate_hash(modified_event)

      assert hash1 != hash2
    end

    test "generates different hashes for different slugs (critical for uniqueness)" do
      base_event = %{
        slug: "event-one",
        title: "Same Title",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      modified_event = %{base_event | slug: "event-two"}

      hash1 = HashGenerator.generate_hash(base_event)
      hash2 = HashGenerator.generate_hash(modified_event)

      assert hash1 != hash2
    end

    test "ensures slug-based uniqueness even with identical titles" do
      event1 = %{
        slug: "tech-meetup-january",
        title: "Tech Meetup",
        cover_image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event2 = %{
        slug: "tech-meetup-february",
        title: "Tech Meetup",  # Same title, different slug
        cover_image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash1 = HashGenerator.generate_hash(event1)
      hash2 = HashGenerator.generate_hash(event2)

      assert hash1 != hash2, "Events with same title but different slugs must have different hashes"
    end

    test "generates different hashes for different image URLs" do
      base_event = %{
        title: "Test Event",
        cover_image_url: "https://example.com/image1.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      modified_event = %{base_event | cover_image_url: "https://example.com/image2.jpg"}

      hash1 = HashGenerator.generate_hash(base_event)
      hash2 = HashGenerator.generate_hash(modified_event)

      assert hash1 != hash2
    end

    test "generates different hashes for different timestamps" do
      base_event = %{
        slug: "time-test-event",
        title: "Test Event",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      modified_event = %{base_event | updated_at: ~N[2023-01-01 13:00:00]}

      hash1 = HashGenerator.generate_hash(base_event)
      hash2 = HashGenerator.generate_hash(modified_event)

      assert hash1 != hash2
    end

    test "handles missing fields gracefully" do
      minimal_event = %{id: 123}

      hash = HashGenerator.generate_hash(minimal_event)

      assert is_binary(hash)
      assert String.length(hash) == 8
    end

    test "handles nil timestamp" do
      event = %{
        title: "Test Event",
        updated_at: nil
      }

      hash = HashGenerator.generate_hash(event)

      assert is_binary(hash)
      assert String.length(hash) == 8
    end

    test "generates different hash for description changes" do
      base_event = %{
        title: "Test Event",
        description: "Original description",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      modified_event = %{base_event | description: "Modified description"}

      hash1 = HashGenerator.generate_hash(base_event)
      hash2 = HashGenerator.generate_hash(modified_event)

      assert hash1 != hash2
    end
  end

  describe "generate_url_path/1" do
    test "generates URL path with event slug and hash" do
      event = %{
        slug: "awesome-tech-meetup",
        title: "Awesome Tech Meetup",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = HashGenerator.generate_url_path(event)

      assert String.starts_with?(path, "/events/awesome-tech-meetup/social-card-")
      assert String.ends_with?(path, ".png")
      assert Regex.match?(~r/\/events\/awesome-tech-meetup\/social-card-[a-f0-9]{8}\.png$/, path)
    end

    test "falls back to ID-based slug when slug is missing" do
      event = %{
        id: 42,
        title: "Test Event",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = HashGenerator.generate_url_path(event)

      assert String.starts_with?(path, "/events/event-42/social-card-")
      assert String.ends_with?(path, ".png")
    end

    test "URL path changes when event data changes" do
      base_event = %{
        slug: "test-event",
        title: "Original Title",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      modified_event = %{base_event | title: "Modified Title"}

      path1 = HashGenerator.generate_url_path(base_event)
      path2 = HashGenerator.generate_url_path(modified_event)

      assert path1 != path2
      # Both should use same slug but different hashes
      assert String.starts_with?(path1, "/events/test-event/social-card-")
      assert String.starts_with?(path2, "/events/test-event/social-card-")
    end
  end

  describe "extract_hash_from_path/1" do
    test "extracts hash from valid social card path" do
      path = "/events/my-event/social-card-a1b2c3d4.png"

      hash = HashGenerator.extract_hash_from_path(path)

      assert hash == "a1b2c3d4"
    end

    test "returns nil for invalid paths" do
      invalid_paths = [
        "/events/my-event/social_card.png",  # Wrong format
        "/events/my-event/social-card-.png", # Missing hash
        "/events/my-event/social-card-abc.png", # Hash too short
        "/events/my-event/social-card-a1b2c3d4e5.png", # Hash too long
        "/invalid/path",
        "",
        "/events/my-event/other-file.png"
      ]

      for path <- invalid_paths do
        assert HashGenerator.extract_hash_from_path(path) == nil
      end
    end

    test "handles complex event slugs" do
      path = "/events/my-awesome-tech-event-2023/social-card-f1e2d3c4.png"

      hash = HashGenerator.extract_hash_from_path(path)

      assert hash == "f1e2d3c4"
    end
  end

  describe "validate_hash/2" do
    test "validates correct hash" do
      event = %{
        title: "Test Event",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash = HashGenerator.generate_hash(event)

      assert HashGenerator.validate_hash(event, hash) == true
    end

    test "rejects incorrect hash" do
      event = %{
        title: "Test Event",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      assert HashGenerator.validate_hash(event, "invalid") == false
      assert HashGenerator.validate_hash(event, "a1b2c3d4") == false
    end

    test "rejects hash when event data changes" do
      original_event = %{
        title: "Original Title",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      modified_event = %{original_event | title: "Modified Title"}
      original_hash = HashGenerator.generate_hash(original_event)

      assert HashGenerator.validate_hash(modified_event, original_hash) == false
    end
  end

  describe "deterministic behavior" do
    test "same data always produces same hash across multiple calls" do
      event = %{
        title: "Consistency Test",
        description: "Testing hash consistency",
        cover_image_url: "https://example.com/consistent.jpg",
        updated_at: ~N[2023-06-01 10:30:00]
      }

      hashes = for _ <- 1..10, do: HashGenerator.generate_hash(event)

      # All hashes should be identical
      assert Enum.uniq(hashes) |> length() == 1
    end

    test "hash remains consistent with map key order changes" do
      # Create the same data in different map construction orders
      event1 = %{
        title: "Order Test",
        updated_at: ~N[2023-01-01 12:00:00],
        cover_image_url: "https://example.com/image.jpg",
        description: "Testing order independence"
      }

      event2 = %{
        description: "Testing order independence",
        cover_image_url: "https://example.com/image.jpg",
        title: "Order Test",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash1 = HashGenerator.generate_hash(event1)
      hash2 = HashGenerator.generate_hash(event2)

      assert hash1 == hash2
    end
  end
end
