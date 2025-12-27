defmodule EventasaurusDiscovery.Scraping.Processors.EventImageCachingTest do
  @moduledoc """
  Tests for the EventImageCaching module.

  Verifies:
  - Source enablement for Wave 1 sources (question-one, pubquiz-pl)
  - Priority assignment for high-priority sources
  - Metadata extraction from scraped data
  - Image caching integration with ImageCacheService
  """
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.CachedImage
  alias EventasaurusDiscovery.Scraping.Processors.EventImageCaching
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "enabled?/1" do
    test "returns true for Wave 1 sources" do
      assert EventImageCaching.enabled?("question-one") == true
      assert EventImageCaching.enabled?("pubquiz-pl") == true
    end

    test "returns false for non-Wave 1 sources" do
      assert EventImageCaching.enabled?("bandsintown") == false
      assert EventImageCaching.enabled?("ticketmaster") == false
      assert EventImageCaching.enabled?("cinema-city") == false
    end

    test "returns false for nil" do
      assert EventImageCaching.enabled?(nil) == false
    end
  end

  describe "priority/1" do
    test "returns 1 for high priority sources" do
      assert EventImageCaching.priority("question-one") == 1
    end

    test "returns 2 for normal priority sources" do
      assert EventImageCaching.priority("pubquiz-pl") == 2
    end

    test "returns 2 for nil" do
      assert EventImageCaching.priority(nil) == 2
    end
  end

  describe "extract_metadata/2" do
    test "extracts metadata from scraped data map" do
      scraped_data = %{
        "title" => "Test Event",
        "description" => "A test event",
        "image_url" => "https://example.com/image.jpg",
        "venue" => "Test Venue"
      }

      metadata = EventImageCaching.extract_metadata(scraped_data, "question-one")

      assert metadata["source_slug"] == "question-one"
      assert is_binary(metadata["extraction_timestamp"])
      assert "description" in metadata["original_keys"]
      assert "title" in metadata["original_keys"]
      assert is_map(metadata["raw_data"])
    end

    test "handles atom keys in scraped data" do
      scraped_data = %{
        title: "Test Event",
        description: "A test event"
      }

      metadata = EventImageCaching.extract_metadata(scraped_data, "pubquiz-pl")

      assert metadata["source_slug"] == "pubquiz-pl"
      assert "description" in metadata["original_keys"]
      assert "title" in metadata["original_keys"]
    end

    test "sanitizes large binary values" do
      large_binary = String.duplicate("x", 15_000)
      scraped_data = %{
        "title" => "Test",
        "large_field" => large_binary
      }

      metadata = EventImageCaching.extract_metadata(scraped_data, "question-one")

      # Large field should be filtered out
      refute Map.has_key?(metadata["raw_data"], "large_field")
      assert Map.has_key?(metadata["raw_data"], "title")
    end

    test "handles non-map scraped data" do
      metadata = EventImageCaching.extract_metadata("not a map", "question-one")

      assert metadata["source_slug"] == "question-one"
      assert metadata["original_keys"] == []
      assert metadata["raw_data"] == nil
    end
  end

  describe "cache_event_image/4" do
    setup do
      # Create test data hierarchy
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
          name: "Question One",
          slug: "question-one",
          website_url: "https://question-one.com",
          priority: 10,
          is_active: true
        })

      {:ok, event} =
        Repo.insert(%PublicEvent{
          title: "Test Event",
          slug: "test-event-#{System.unique_integer([:positive])}",
          venue_id: venue.id,
          starts_at: DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second)
        })

      {:ok, event_source} =
        Repo.insert(%PublicEventSource{
          event_id: event.id,
          source_id: source.id,
          external_id: "test-ext-#{System.unique_integer([:positive])}",
          source_url: "https://example.com/event",
          image_url: "https://example.com/image.jpg",
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      %{
        event: event,
        event_source: event_source,
        source: source,
        venue: venue,
        city: city,
        country: country
      }
    end

    test "returns fallback for nil image_url" do
      assert {:fallback, nil} = EventImageCaching.cache_event_image(nil, 123, "question-one", %{})
    end

    test "returns fallback for disabled sources" do
      result = EventImageCaching.cache_event_image(
        "https://example.com/image.jpg",
        123,
        "bandsintown",
        %{}
      )

      assert {:fallback, "https://example.com/image.jpg"} = result
    end

    test "queues image for caching for enabled sources", %{event_source: event_source} do
      image_url = "https://question-one.com/events/image.jpg"
      scraped_data = %{"title" => "Test", "venue" => "Bar"}

      result = EventImageCaching.cache_event_image(
        image_url,
        event_source.id,
        "question-one",
        scraped_data
      )

      # Should return :ok with original URL (image queued for caching)
      assert {:ok, ^image_url} = result

      # Verify CachedImage record was created
      cached = Repo.get_by(CachedImage,
        entity_type: "public_event_source",
        entity_id: event_source.id,
        position: 0
      )

      assert cached != nil
      assert cached.original_url == image_url
      assert cached.status == "pending"
      assert cached.original_source == "question-one"
    end

    test "returns cached URL if image already cached", %{event_source: event_source} do
      image_url = "https://question-one.com/events/already-cached.jpg"
      cdn_url = "https://cdn.example.com/cached-image.jpg"

      # Pre-create a cached image record
      {:ok, _cached} = Repo.insert(%CachedImage{
        entity_type: "public_event_source",
        entity_id: event_source.id,
        position: 0,
        original_url: image_url,
        status: "cached",
        cdn_url: cdn_url,
        r2_key: "images/test.jpg"
      })

      result = EventImageCaching.cache_event_image(
        image_url,
        event_source.id,
        "question-one",
        %{}
      )

      assert {:cached, ^cdn_url} = result
    end
  end

  describe "enabled_sources/0" do
    test "returns list of enabled sources" do
      sources = EventImageCaching.enabled_sources()

      assert is_list(sources)
      assert "question-one" in sources
      assert "pubquiz-pl" in sources
    end
  end

  describe "stats/0" do
    test "returns statistics map" do
      stats = EventImageCaching.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :overall)
      assert Map.has_key?(stats, :enabled_sources)
      assert Map.has_key?(stats, :high_priority_sources)
    end
  end
end
