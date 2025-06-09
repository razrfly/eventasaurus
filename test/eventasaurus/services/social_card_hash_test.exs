defmodule Eventasaurus.Services.SocialCardHashTest do
  use ExUnit.Case, async: true

  alias Eventasaurus.Services.SocialCardHash

  describe "generate_hash/1" do
    test "generates consistent hash for same event data" do
      event = %{
        image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash1 = SocialCardHash.generate_hash(event)
      hash2 = SocialCardHash.generate_hash(event)

      assert hash1 == hash2
      assert String.length(hash1) == 8
      assert hash1 =~ ~r/^[a-f0-9]{8}$/
    end

    test "generates different hashes for different image URLs" do
      event1 = %{
        image_url: "https://example.com/image1.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event2 = %{
        image_url: "https://example.com/image2.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash1 = SocialCardHash.generate_hash(event1)
      hash2 = SocialCardHash.generate_hash(event2)

      assert hash1 != hash2
    end

    test "generates different hashes for different timestamps" do
      event1 = %{
        image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event2 = %{
        image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-02 12:00:00]
      }

      hash1 = SocialCardHash.generate_hash(event1)
      hash2 = SocialCardHash.generate_hash(event2)

      assert hash1 != hash2
    end

    test "handles event with only image_url (no updated_at)" do
      event = %{image_url: "https://example.com/image.jpg"}

      hash = SocialCardHash.generate_hash(event)

      assert String.length(hash) == 8
      assert hash =~ ~r/^[a-f0-9]{8}$/
    end

    test "handles event with missing fields" do
      hash = SocialCardHash.generate_hash(%{})

      assert String.length(hash) == 8
      assert hash =~ ~r/^[a-f0-9]{8}$/
    end

    test "handles nil image_url gracefully" do
      event = %{
        image_url: nil,
        updated_at: ~N[2023-01-01 12:00:00]
      }

      hash = SocialCardHash.generate_hash(event)

      assert String.length(hash) == 8
      assert hash =~ ~r/^[a-f0-9]{8}$/
    end
  end

  describe "generate_filename/2" do
    test "generates filename with event ID and hash" do
      event = %{
        image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      filename = SocialCardHash.generate_filename("123", event)

      assert filename =~ ~r/^123-[a-f0-9]{8}\.png$/
    end

    test "generates different filenames for different events" do
      event1 = %{
        image_url: "https://example.com/image1.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event2 = %{
        image_url: "https://example.com/image2.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      filename1 = SocialCardHash.generate_filename("123", event1)
      filename2 = SocialCardHash.generate_filename("123", event2)

      assert filename1 != filename2
    end

    test "generates different filenames for different event IDs" do
      event = %{
        image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      filename1 = SocialCardHash.generate_filename("123", event)
      filename2 = SocialCardHash.generate_filename("456", event)

      assert filename1 != filename2
      assert filename1 =~ ~r/^123-/
      assert filename2 =~ ~r/^456-/
    end
  end

  describe "generate_temp_path/3" do
    test "generates temp path with default png extension" do
      event = %{
        image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = SocialCardHash.generate_temp_path("123", event)

      assert String.starts_with?(path, System.tmp_dir!())
      assert String.contains?(path, "eventasaurus_123_")
      assert String.ends_with?(path, ".png")
    end

    test "generates temp path with custom extension" do
      event = %{
        image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path = SocialCardHash.generate_temp_path("123", event, "svg")

      assert String.starts_with?(path, System.tmp_dir!())
      assert String.contains?(path, "eventasaurus_123_")
      assert String.ends_with?(path, ".svg")
    end

    test "generates different paths for different events" do
      event1 = %{
        image_url: "https://example.com/image1.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      event2 = %{
        image_url: "https://example.com/image2.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      path1 = SocialCardHash.generate_temp_path("123", event1)
      path2 = SocialCardHash.generate_temp_path("123", event2)

      assert path1 != path2
    end
  end
end
