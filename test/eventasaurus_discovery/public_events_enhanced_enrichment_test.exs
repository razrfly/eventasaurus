defmodule EventasaurusDiscovery.PublicEventsEnhancedEnrichmentTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Venues.Venue

  import Ecto.Query

  describe "preload_for_image_enrichment/1" do
    test "preloads required associations for image enrichment" do
      # Create test data
      country = insert(:country)
      city = insert(:city, country: country, unsplash_gallery: %{"general" => ["image1.jpg"]})
      venue = insert(:venue, city_ref: city)
      category = insert(:category)
      source = insert(:source)

      event =
        insert(:public_event,
          venue: venue,
          categories: [category],
          sources: [source],
          movies: []
        )

      # Fetch event without preloads
      event_without_preloads = Repo.get!(PublicEvent, event.id)

      # Apply preload helper
      enriched_event = PublicEventsEnhanced.preload_for_image_enrichment(event_without_preloads)

      # Verify preloads are present
      assert Ecto.assoc_loaded?(enriched_event.sources)
      assert Ecto.assoc_loaded?(enriched_event.movies)
      assert Ecto.assoc_loaded?(enriched_event.categories)
      assert Ecto.assoc_loaded?(enriched_event.venue)
      assert Ecto.assoc_loaded?(enriched_event.venue.city_ref)
      # unsplash_gallery is a JSONB field, not an association, so no need to check if loaded
    end

    test "works with a list of events" do
      country = insert(:country)
      city = insert(:city, country: country)
      venue = insert(:venue, city_ref: city)

      events = [
        insert(:public_event, venue: venue),
        insert(:public_event, venue: venue)
      ]

      event_ids = Enum.map(events, & &1.id)

      # Fetch events without preloads
      events_without_preloads =
        from(e in PublicEvent, where: e.id in ^event_ids)
        |> Repo.all()

      # Apply preload helper
      enriched_events =
        PublicEventsEnhanced.preload_for_image_enrichment(events_without_preloads)

      # Verify all events have preloads
      Enum.each(enriched_events, fn event ->
        assert Ecto.assoc_loaded?(event.sources)
        assert Ecto.assoc_loaded?(event.venue)
        assert Ecto.assoc_loaded?(event.venue.city_ref)
      end)
    end

    test "works with an Ecto query" do
      country = insert(:country)
      city = insert(:city, country: country)
      venue = insert(:venue, city_ref: city)
      event = insert(:public_event, venue: venue)

      # Apply preload helper to query
      query = from(e in PublicEvent, where: e.id == ^event.id)
      enriched_events = query |> PublicEventsEnhanced.preload_for_image_enrichment() |> Repo.all()

      # Verify preloads
      assert length(enriched_events) == 1
      enriched_event = List.first(enriched_events)
      assert Ecto.assoc_loaded?(enriched_event.venue)
      assert Ecto.assoc_loaded?(enriched_event.venue.city_ref)
    end
  end

  describe "enrich_event_images/2 with :browsing_city strategy" do
    test "enriches all events with browsing city's Unsplash images" do
      # Create two cities with different Unsplash galleries
      country = insert(:country)

      london =
        insert(:city,
          name: "London",
          country: country,
          unsplash_gallery: %{"general" => ["london1.jpg", "london2.jpg"]}
        )

      paris =
        insert(:city,
          name: "Paris",
          country: country,
          unsplash_gallery: %{"general" => ["paris1.jpg", "paris2.jpg"]}
        )

      london_venue = insert(:venue, city_ref: london)
      paris_venue = insert(:venue, city_ref: paris)

      # Create events in different cities without source images
      london_event =
        insert(:public_event,
          venue: london_venue,
          sources: [insert(:source, image_url: nil)],
          movies: []
        )
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      paris_event =
        insert(:public_event,
          venue: paris_venue,
          sources: [insert(:source, image_url: nil)],
          movies: []
        )
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      # Enrich with London as browsing city (both events should use London images)
      enriched_events =
        PublicEventsEnhanced.enrich_event_images([london_event, paris_event],
          strategy: :browsing_city,
          browsing_city_id: london.id
        )

      # Both events should have cover_image_url (from London's gallery)
      Enum.each(enriched_events, fn event ->
        assert event.cover_image_url != nil
        # Should contain "london" in URL path (from Unsplash gallery)
        assert String.contains?(event.cover_image_url, "london")
      end)
    end

    test "preserves existing cover_image_url unless force: true" do
      country = insert(:country)
      city = insert(:city, country: country, unsplash_gallery: %{"general" => ["city.jpg"]})
      venue = insert(:venue, city_ref: city)

      event =
        insert(:public_event,
          venue: venue,
          cover_image_url: "https://existing-image.jpg",
          sources: [],
          movies: []
        )
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      # Without force, should preserve existing
      enriched =
        PublicEventsEnhanced.enrich_event_images([event],
          strategy: :browsing_city,
          browsing_city_id: city.id
        )

      assert List.first(enriched).cover_image_url == "https://existing-image.jpg"

      # With force, should re-enrich
      enriched_forced =
        PublicEventsEnhanced.enrich_event_images([event],
          strategy: :browsing_city,
          browsing_city_id: city.id,
          force: true
        )

      refute List.first(enriched_forced).cover_image_url == "https://existing-image.jpg"
    end

    test "handles missing browsing city gracefully" do
      country = insert(:country)
      city = insert(:city, country: country)
      venue = insert(:venue, city_ref: city)

      event =
        insert(:public_event, venue: venue, sources: [], movies: [])
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      # Non-existent city ID
      enriched =
        PublicEventsEnhanced.enrich_event_images([event],
          strategy: :browsing_city,
          browsing_city_id: 999_999
        )

      # Should return events unchanged
      assert enriched == [event]
    end
  end

  describe "enrich_event_images/2 with :own_city strategy" do
    test "each event uses its own venue's city for enrichment" do
      # Create two cities with different Unsplash galleries
      country = insert(:country)

      london =
        insert(:city,
          name: "London",
          country: country,
          unsplash_gallery: %{"general" => ["london1.jpg", "london2.jpg"]}
        )

      paris =
        insert(:city,
          name: "Paris",
          country: country,
          unsplash_gallery: %{"general" => ["paris1.jpg", "paris2.jpg"]}
        )

      london_venue = insert(:venue, name: "London Venue", city_ref: london)
      paris_venue = insert(:venue, name: "Paris Venue", city_ref: paris)

      # Create events without source images
      london_event =
        insert(:public_event,
          venue: london_venue,
          sources: [insert(:source, image_url: nil)],
          movies: []
        )
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      paris_event =
        insert(:public_event,
          venue: paris_venue,
          sources: [insert(:source, image_url: nil)],
          movies: []
        )
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      # Enrich with own_city strategy
      enriched_events =
        PublicEventsEnhanced.enrich_event_images([london_event, paris_event],
          strategy: :own_city
        )

      # Each event should use its own city's gallery
      london_enriched = Enum.find(enriched_events, &(&1.id == london_event.id))
      paris_enriched = Enum.find(enriched_events, &(&1.id == paris_event.id))

      assert london_enriched.cover_image_url != nil
      assert paris_enriched.cover_image_url != nil

      # Verify they got different images (from different cities)
      assert String.contains?(london_enriched.cover_image_url, "london")
      assert String.contains?(paris_enriched.cover_image_url, "paris")
    end

    test "handles events without venues gracefully" do
      # Event without venue (virtual event)
      event =
        insert(:public_event, venue: nil, sources: [], movies: [])
        |> Repo.preload([:sources, :movies, :categories])

      enriched = PublicEventsEnhanced.enrich_event_images([event], strategy: :own_city)

      # Should return event unchanged (no venue to get city from)
      assert List.first(enriched).cover_image_url == nil
    end

    test "emits telemetry for missing Unsplash gallery" do
      country = insert(:country)
      # City without Unsplash gallery
      city = insert(:city, country: country, unsplash_gallery: nil)
      venue = insert(:venue, city_ref: city)

      event =
        insert(:public_event, venue: venue, sources: [], movies: [])
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      # Attach telemetry handler to capture events
      test_pid = self()

      :telemetry.attach(
        "test-missing-gallery",
        [:eventasaurus, :unsplash, :fallback_missing],
        fn _event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      # Enrich event (should emit telemetry)
      PublicEventsEnhanced.enrich_event_images([event], strategy: :own_city)

      # Verify telemetry event was emitted
      assert_receive {:telemetry_event, %{count: 1}, %{city_id: _, event_id: _}}, 1000

      # Cleanup
      :telemetry.detach("test-missing-gallery")
    end
  end

  describe "enrich_event_images/2 with :skip strategy" do
    test "returns events unchanged" do
      country = insert(:country)
      city = insert(:city, country: country, unsplash_gallery: %{"general" => ["image.jpg"]})
      venue = insert(:venue, city_ref: city)

      event =
        insert(:public_event, venue: venue, sources: [], movies: [])
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      enriched = PublicEventsEnhanced.enrich_event_images([event], strategy: :skip)

      # Should be identical
      assert enriched == [event]
      assert List.first(enriched).cover_image_url == nil
    end
  end

  describe "enrich_event_images/2 with invalid strategy" do
    test "falls back to :own_city strategy with warning" do
      country = insert(:country)

      city =
        insert(:city, country: country, unsplash_gallery: %{"general" => ["image.jpg"]})

      venue = insert(:venue, city_ref: city)

      event =
        insert(:public_event,
          venue: venue,
          sources: [insert(:source, image_url: nil)],
          movies: []
        )
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      # Use invalid strategy
      enriched = PublicEventsEnhanced.enrich_event_images([event], strategy: :invalid_strategy)

      # Should fall back to :own_city and still enrich
      assert List.first(enriched).cover_image_url != nil
    end
  end

  describe "enrich_event_images/2 with source images" do
    test "preserves source images when present" do
      country = insert(:country)
      city = insert(:city, country: country, unsplash_gallery: %{"general" => ["city.jpg"]})
      venue = insert(:venue, city_ref: city)

      event =
        insert(:public_event,
          venue: venue,
          sources: [insert(:source, image_url: "https://source-image.jpg")],
          movies: []
        )
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      enriched = PublicEventsEnhanced.enrich_event_images([event], strategy: :own_city)

      # Should use source image, not Unsplash fallback
      assert List.first(enriched).cover_image_url == "https://source-image.jpg"
    end
  end

  describe "enrich_event_images/2 integration with get_cover_image_url" do
    test "correctly applies existing image selection logic" do
      country = insert(:country)
      city = insert(:city, country: country, unsplash_gallery: %{"general" => ["city.jpg"]})
      venue = insert(:venue, city_ref: city)

      # Event with movie (should prioritize movie image)
      movie = insert(:movie, poster_url: "https://tmdb-poster.jpg")

      event =
        insert(:public_event,
          venue: venue,
          movies: [movie],
          sources: [insert(:source, image_url: "https://source-image.jpg")]
        )
        |> Repo.preload([:sources, :movies, :categories, venue: :city_ref])

      enriched = PublicEventsEnhanced.enrich_event_images([event], strategy: :own_city)

      # Should prioritize movie image per existing logic
      assert List.first(enriched).cover_image_url == "https://tmdb-poster.jpg"
    end
  end
end
