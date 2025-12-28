defmodule EventasaurusApp.Images.PerformerImagesTest do
  @moduledoc """
  Tests for PerformerImages virtual lookup module.

  Verifies that performer images are correctly derived from event source
  cached images without separate performer image caching.
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

  describe "get_images/1" do
    test "returns empty list when no cached images exist", %{performer: performer} do
      assert PerformerImages.get_images(performer.id) == []
    end

    test "returns cached images from event sources", %{
      performer: performer,
      event_source: event_source
    } do
      # Create cached image for the event source
      {:ok, cached} =
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

      images = PerformerImages.get_images(performer.id)

      assert length(images) == 1
      assert hd(images).id == cached.id
      assert hd(images).cdn_url == "https://cdn.example.com/cached.jpg"
    end

    test "excludes pending/failed images", %{performer: performer, event_source: event_source} do
      # Create pending image (should not be returned)
      {:ok, _pending} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 0,
          original_url: "https://bandsintown.com/pending.jpg",
          status: "pending",
          original_source: "bandsintown"
        })

      # Create failed image (should not be returned)
      {:ok, _failed} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source.id,
          position: 1,
          original_url: "https://bandsintown.com/failed.jpg",
          status: "failed",
          last_error: "HTTP 404",
          original_source: "bandsintown"
        })

      images = PerformerImages.get_images(performer.id)
      assert images == []
    end

    test "returns distinct images by original_url", %{performer: performer} do
      # Create two event sources with the same image URL
      {:ok, source2} =
        Repo.insert(%Source{
          name: "Question One",
          slug: "question-one",
          website_url: "https://question-one.com",
          priority: 10,
          is_active: true
        })

      {:ok, event2} =
        Repo.insert(%PublicEvent{
          title: "Test Concert 2",
          slug: "test-concert-2-#{System.unique_integer([:positive])}",
          venue_id: Repo.all(Venue) |> hd() |> Map.get(:id),
          starts_at: DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)
        })

      {:ok, event_source2} =
        Repo.insert(%PublicEventSource{
          event_id: event2.id,
          source_id: source2.id,
          external_id: "test-ext-2-#{System.unique_integer([:positive])}",
          source_url: "https://question-one.com/event/456",
          image_url: "https://same-image.jpg",
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, _event_performer2} =
        Repo.insert(%PublicEventPerformer{
          event_id: event2.id,
          performer_id: performer.id
        })

      # Cache the same image from both sources
      {:ok, _cached1} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: Repo.all(PublicEventSource) |> hd() |> Map.get(:id),
          position: 0,
          original_url: "https://same-image.jpg",
          cdn_url: "https://cdn.example.com/same.jpg",
          r2_key: "images/same.jpg",
          status: "cached",
          original_source: "bandsintown"
        })

      {:ok, _cached2} =
        Repo.insert(%CachedImage{
          entity_type: "public_event_source",
          entity_id: event_source2.id,
          position: 0,
          original_url: "https://same-image.jpg",
          cdn_url: "https://cdn.example.com/same.jpg",
          r2_key: "images/same2.jpg",
          status: "cached",
          original_source: "question-one"
        })

      images = PerformerImages.get_images(performer.id)

      # Should return only one image due to distinct on original_url
      assert length(images) == 1
    end
  end

  describe "get_primary_image/1" do
    test "returns nil when no cached images exist", %{performer: performer} do
      assert PerformerImages.get_primary_image(performer.id) == nil
    end

    test "returns the most recent cached image", %{
      performer: performer,
      event_source: event_source
    } do
      {:ok, cached} =
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

      image = PerformerImages.get_primary_image(performer.id)

      assert image.id == cached.id
      assert image.cdn_url == "https://cdn.example.com/cached.jpg"
    end
  end

  describe "get_url/1" do
    test "returns nil when no cached images exist", %{performer: performer} do
      assert PerformerImages.get_url(performer.id) == nil
    end

    test "returns CDN URL when cached image exists", %{
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

      assert PerformerImages.get_url(performer.id) == "https://cdn.example.com/cached.jpg"
    end
  end

  describe "get_url_with_fallback/2" do
    test "returns fallback when no cached images exist", %{performer: performer} do
      fallback = "https://original.example.com/fallback.jpg"

      assert PerformerImages.get_url_with_fallback(performer.id, fallback) == fallback
    end

    test "returns CDN URL when cached image exists", %{
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

      assert PerformerImages.get_url_with_fallback(performer.id, fallback) ==
               "https://cdn.example.com/cached.jpg"
    end

    test "returns nil when no cached images and fallback is nil", %{performer: performer} do
      assert PerformerImages.get_url_with_fallback(performer.id, nil) == nil
    end
  end

  describe "get_urls/1" do
    test "returns empty map for empty list" do
      assert PerformerImages.get_urls([]) == %{}
    end

    test "returns map of performer_id => cdn_url", %{
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

      urls = PerformerImages.get_urls([performer.id])

      assert Map.has_key?(urls, performer.id)
      assert urls[performer.id] == "https://cdn.example.com/cached.jpg"
    end

    test "handles multiple performers", %{
      performer: performer,
      event_source: event_source
    } do
      # Create second performer without cached image
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

      urls = PerformerImages.get_urls([performer.id, performer2.id])

      # First performer has cached image
      assert urls[performer.id] == "https://cdn.example.com/cached.jpg"

      # Second performer has no cached image (key not present)
      refute Map.has_key?(urls, performer2.id)
    end
  end

  describe "get_urls_with_fallbacks/1" do
    test "returns empty map for empty input" do
      assert PerformerImages.get_urls_with_fallbacks(%{}) == %{}
    end

    test "uses cached URL when available, fallback otherwise", %{
      performer: performer,
      event_source: event_source
    } do
      # Create second performer without cached image
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

      # First performer uses cached URL
      assert urls[performer.id] == "https://cdn.example.com/cached.jpg"

      # Second performer uses fallback
      assert urls[performer2.id] == "https://fallback2.jpg"
    end
  end

  describe "count_images/1" do
    test "returns 0 when no cached images exist", %{performer: performer} do
      assert PerformerImages.count_images(performer.id) == 0
    end

    test "returns count of cached images", %{performer: performer, event_source: event_source} do
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

      assert PerformerImages.count_images(performer.id) == 1
    end
  end
end
