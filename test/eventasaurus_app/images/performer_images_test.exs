defmodule EventasaurusApp.Images.PerformerImagesTest do
  @moduledoc """
  Tests for PerformerImages virtual lookup module.

  Verifies that performer images are correctly derived from event source
  cached images without separate performer image caching.

  NOTE: In non-production environments (test/dev), PerformerImages skips
  cache lookups entirely and returns empty results. This prevents dev/test
  from querying a cache that doesn't exist and avoids polluting production
  R2 buckets. These tests verify that fallback behavior.
  """
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.CachedImage
  alias EventasaurusApp.Images.PerformerImages
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource, PublicEventPerformer}
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country}

  setup do
    # Create base location data
    {:ok, country} =
      Repo.insert(%Country{
        name: "Poland",
        code: "PL",
        slug: "poland-#{System.unique_integer([:positive])}"
      })

    {:ok, city} =
      Repo.insert(%City{
        name: "Warsaw",
        slug: "warsaw-#{System.unique_integer([:positive])}",
        country_id: country.id,
        latitude: 52.2297,
        longitude: 21.0122
      })

    {:ok, venue} =
      Repo.insert(%Venue{
        name: "Test Venue",
        slug: "test-venue-#{System.unique_integer([:positive])}",
        city_id: city.id,
        address: "Test Address",
        latitude: 52.2297,
        longitude: 21.0122
      })

    {:ok, source} =
      Repo.insert(%Source{
        name: "Bandsintown",
        slug: "bandsintown",
        website_url: "https://bandsintown.com",
        priority: 10,
        is_active: true
      })

    {:ok, performer} =
      Repo.insert(%Performer{
        name: "Test Artist",
        slug: "test-artist-#{System.unique_integer([:positive])}",
        image_url: "https://original.example.com/artist.jpg"
      })

    {:ok, event} =
      Repo.insert(%PublicEvent{
        title: "Test Concert",
        slug: "test-concert-#{System.unique_integer([:positive])}",
        venue_id: venue.id,
        starts_at: DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second)
      })

    {:ok, event_source} =
      Repo.insert(%PublicEventSource{
        event_id: event.id,
        source_id: source.id,
        external_id: "test-ext-#{System.unique_integer([:positive])}",
        source_url: "https://bandsintown.com/event/123",
        image_url: "https://bandsintown.com/image.jpg",
        last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _event_performer} =
      Repo.insert(%PublicEventPerformer{
        event_id: event.id,
        performer_id: performer.id
      })

    %{
      performer: performer,
      event: event,
      event_source: event_source,
      source: source,
      venue: venue,
      city: city,
      country: country
    }
  end

  describe "get_images/1 (test environment - no cache lookup)" do
    test "returns empty list when no cached images exist", %{performer: performer} do
      assert PerformerImages.get_images(performer.id) == []
    end

    test "returns empty list even when images are cached (test mode skips cache)", %{
      performer: performer,
      event_source: event_source
    } do
      # Create cached image for the event source
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/image.jpg",
          cdn_url: "https://cdn.example.com/cached.jpg",
          r2_key: "images/test.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      # In test mode, cache not queried - returns empty list
      images = PerformerImages.get_images(performer.id)
      assert images == []
    end

    test "pending/failed images also result in empty list (test mode)", %{
      performer: performer,
      event_source: event_source
    } do
      # Create pending image
      {:ok, _pending} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/pending.jpg",
          status: "pending",
          original_source: "bandsintown"
        })

      # In test mode, returns empty list
      images = PerformerImages.get_images(performer.id)
      assert images == []
    end
  end

  describe "get_primary_image/1 (test environment - no cache lookup)" do
    test "returns nil when no cached images exist", %{performer: performer} do
      assert PerformerImages.get_primary_image(performer.id) == nil
    end

    test "returns nil even when image is cached (test mode skips cache)", %{
      performer: performer,
      event_source: event_source
    } do
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/image.jpg",
          cdn_url: "https://cdn.example.com/cached.jpg",
          r2_key: "images/test.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      # In test mode, cache not queried - returns nil
      image = PerformerImages.get_primary_image(performer.id)
      assert image == nil
    end
  end

  describe "get_url/1 (test environment - no cache lookup)" do
    test "returns nil when no cached images exist", %{performer: performer} do
      assert PerformerImages.get_url(performer.id) == nil
    end

    test "returns nil even when cached image exists (test mode skips cache)", %{
      performer: performer,
      event_source: event_source
    } do
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/image.jpg",
          cdn_url: "https://cdn.example.com/cached.jpg",
          r2_key: "images/test.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      # In test mode, cache not queried - returns nil
      assert PerformerImages.get_url(performer.id) == nil
    end
  end

  describe "get_url_with_fallback/2 (test environment)" do
    test "returns fallback when no cached images exist", %{performer: performer} do
      fallback = "https://original.example.com/fallback.jpg"

      assert PerformerImages.get_url_with_fallback(performer.id, fallback) == fallback
    end

    test "returns fallback even when cached image exists (test mode)", %{
      performer: performer,
      event_source: event_source
    } do
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/image.jpg",
          cdn_url: "https://cdn.example.com/cached.jpg",
          r2_key: "images/test.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      fallback = "https://original.example.com/fallback.jpg"

      # In test mode, cache not queried - returns fallback
      assert PerformerImages.get_url_with_fallback(performer.id, fallback) == fallback
    end

    test "returns nil when no cached images and fallback is nil", %{performer: performer} do
      assert PerformerImages.get_url_with_fallback(performer.id, nil) == nil
    end
  end

  describe "get_urls/1 (test environment - no cache lookup)" do
    test "returns empty map for empty list" do
      assert PerformerImages.get_urls([]) == %{}
    end

    test "returns empty map in test mode (cache not queried)", %{
      performer: performer,
      event_source: event_source
    } do
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/image.jpg",
          cdn_url: "https://cdn.example.com/cached.jpg",
          r2_key: "images/test.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      # In test mode, cache not queried - returns empty map
      urls = PerformerImages.get_urls([performer.id])
      assert urls == %{}
    end

    test "handles multiple performers (all return empty in test mode)", %{
      performer: performer,
      event_source: event_source
    } do
      # Create second performer
      {:ok, performer2} =
        Repo.insert(%Performer{
          name: "Test Artist 2",
          slug: "test-artist-2-#{System.unique_integer([:positive])}",
          image_url: "https://original.example.com/artist2.jpg"
        })

      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/image.jpg",
          cdn_url: "https://cdn.example.com/cached.jpg",
          r2_key: "images/test.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      # In test mode, returns empty map for all performers
      urls = PerformerImages.get_urls([performer.id, performer2.id])
      assert urls == %{}
    end
  end

  describe "get_urls_with_fallbacks/1 (test environment)" do
    test "returns empty map for empty input" do
      assert PerformerImages.get_urls_with_fallbacks(%{}) == %{}
    end

    test "returns fallbacks directly in test mode", %{
      performer: performer,
      event_source: event_source
    } do
      # Create second performer
      {:ok, performer2} =
        Repo.insert(%Performer{
          name: "Test Artist 2",
          slug: "test-artist-2-#{System.unique_integer([:positive])}",
          image_url: "https://original.example.com/artist2.jpg"
        })

      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/image.jpg",
          cdn_url: "https://cdn.example.com/cached.jpg",
          r2_key: "images/test.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      fallbacks = %{
        performer.id => "https://fallback1.jpg",
        performer2.id => "https://fallback2.jpg"
      }

      urls = PerformerImages.get_urls_with_fallbacks(fallbacks)

      # In test mode, fallbacks are returned as-is (no cache lookup)
      assert urls[performer.id] == "https://fallback1.jpg"
      assert urls[performer2.id] == "https://fallback2.jpg"
    end

    test "preserves nil fallbacks", %{performer: performer} do
      fallbacks = %{performer.id => nil}

      urls = PerformerImages.get_urls_with_fallbacks(fallbacks)

      assert urls[performer.id] == nil
    end
  end

  describe "count_images/1 (test environment - no cache lookup)" do
    test "returns 0 when no cached images exist", %{performer: performer} do
      assert PerformerImages.count_images(performer.id) == 0
    end

    test "returns 0 even when images are cached (test mode)", %{
      performer: performer,
      event_source: event_source
    } do
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/image.jpg",
          cdn_url: "https://cdn.example.com/cached.jpg",
          r2_key: "images/test.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      # In test mode, cache not queried - returns 0
      assert PerformerImages.count_images(performer.id) == 0
    end
  end
end
