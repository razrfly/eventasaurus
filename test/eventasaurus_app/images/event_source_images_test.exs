defmodule EventasaurusApp.Images.EventSourceImagesTest do
  @moduledoc """
  Tests for EventSourceImages module.

  Verifies that event source image URLs are correctly retrieved
  with proper fallback behavior.

  NOTE: In non-production environments (test/dev), EventSourceImages skips
  cache lookups entirely and returns fallbacks directly. This prevents
  dev/test from querying a cache that doesn't exist and avoids polluting
  production R2 buckets. These tests verify that fallback behavior.
  """
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.CachedImage
  alias EventasaurusApp.Images.EventSourceImages

  # Use unique integer IDs for each test to avoid collisions
  defp unique_id, do: System.unique_integer([:positive])

  describe "get_url/2 (test environment - no cache lookup)" do
    test "returns fallback when no cached image exists" do
      source_id = unique_id()
      fallback = "https://example.com/fallback.jpg"
      assert EventSourceImages.get_url(source_id, fallback) == fallback
    end

    test "returns nil when no cached image and no fallback" do
      source_id = unique_id()
      assert EventSourceImages.get_url(source_id) == nil
    end

    test "returns fallback even when image is cached (test mode skips cache)" do
      source_id = unique_id()

      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: source_id,
          position: 0,
          original_url: "https://example.com/source.jpg",
          cdn_url: "https://cdn.example.com/source.jpg",
          r2_key: "images/public_event_source/source.jpg",
          status: "cached",
          original_source: "scraper"
        })

      # In test mode, cache not queried - fallback returned
      assert EventSourceImages.get_url(source_id, "fallback") == "fallback"
    end

    test "returns fallback when image is pending (test mode)" do
      source_id = unique_id()

      {:ok, _pending} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: source_id,
          position: 0,
          original_url: "https://example.com/source.jpg",
          status: "pending",
          original_source: "scraper"
        })

      # In test mode, cache not queried - fallback returned
      assert EventSourceImages.get_url(source_id, "my_fallback") == "my_fallback"
    end

    test "returns fallback when image is failed (test mode)" do
      source_id = unique_id()

      {:ok, _failed} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: source_id,
          position: 0,
          original_url: "https://example.com/source.jpg",
          status: "failed",
          last_error: "HTTP 404",
          original_source: "scraper"
        })

      # In test mode, cache not queried - fallback returned
      assert EventSourceImages.get_url(source_id, "my_fallback") == "my_fallback"
    end
  end

  describe "get_urls/1 (test environment - no cache lookup)" do
    test "returns empty map for empty list" do
      assert EventSourceImages.get_urls([]) == %{}
    end

    test "returns empty map in test mode (cache not queried)" do
      source1_id = unique_id()
      source2_id = unique_id()

      {:ok, _cached1} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: source1_id,
          position: 0,
          original_url: "https://example.com/source1.jpg",
          cdn_url: "https://cdn.example.com/source1.jpg",
          r2_key: "images/public_event_source/source1.jpg",
          status: "cached",
          original_source: "scraper"
        })

      {:ok, _cached2} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: source2_id,
          position: 0,
          original_url: "https://example.com/source2.jpg",
          cdn_url: "https://cdn.example.com/source2.jpg",
          r2_key: "images/public_event_source/source2.jpg",
          status: "cached",
          original_source: "scraper"
        })

      # In test mode, cache not queried - returns empty map
      urls = EventSourceImages.get_urls([source1_id, source2_id])
      assert urls == %{}
    end

    test "pending/failed records also result in empty map (test mode)" do
      source_id = unique_id()

      # Insert a pending record
      {:ok, _pending} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: source_id,
          position: 0,
          original_url: "https://example.com/source1.jpg",
          status: "pending",
          original_source: "scraper"
        })

      # In test mode, returns empty map
      urls = EventSourceImages.get_urls([source_id])
      assert urls == %{}
    end
  end

  describe "get_urls_with_fallbacks/1 (test environment)" do
    test "returns empty map for empty input" do
      assert EventSourceImages.get_urls_with_fallbacks(%{}) == %{}
    end

    test "returns fallbacks directly in test mode" do
      source1_id = unique_id()
      source2_id = unique_id()

      # Cache source1's image
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: source1_id,
          position: 0,
          original_url: "https://example.com/source1.jpg",
          cdn_url: "https://cdn.example.com/source1.jpg",
          r2_key: "images/public_event_source/source1.jpg",
          status: "cached",
          original_source: "scraper"
        })

      fallbacks = %{
        source1_id => "https://fallback1.jpg",
        source2_id => "https://fallback2.jpg"
      }

      urls = EventSourceImages.get_urls_with_fallbacks(fallbacks)

      # In test mode, fallbacks are returned as-is (no cache lookup)
      assert urls[source1_id] == "https://fallback1.jpg"
      assert urls[source2_id] == "https://fallback2.jpg"
    end

    test "preserves nil fallbacks" do
      source_id = unique_id()
      fallbacks = %{source_id => nil}

      urls = EventSourceImages.get_urls_with_fallbacks(fallbacks)

      assert urls[source_id] == nil
    end
  end
end
