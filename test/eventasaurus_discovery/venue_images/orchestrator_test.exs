defmodule EventasaurusDiscovery.VenueImages.OrchestratorTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.VenueImages.Orchestrator
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider
  alias EventasaurusApp.Venues.Venue

  describe "fetch_venue_images/1" do
    setup do
      # Clean up providers
      Repo.delete_all(GeocodingProvider)

      # Create test providers with image capability
      google = %GeocodingProvider{
        name: "google_places",
        is_active: true,
        capabilities: %{"images" => true, "geocoding" => true},
        priorities: %{"images" => 1},
        metadata: %{"cost_per_image" => 0.003, "rate_limits" => %{"per_second" => 10}}
      }

      foursquare = %GeocodingProvider{
        name: "foursquare",
        is_active: true,
        capabilities: %{"images" => true, "geocoding" => true},
        priorities: %{"images" => 2},
        metadata: %{"cost_per_image" => 0.0, "rate_limits" => %{"per_minute" => 100}}
      }

      Repo.insert!(google)
      Repo.insert!(foursquare)

      venue_input = %{
        name: "Test Venue",
        latitude: 40.7308,
        longitude: -74.0007,
        provider_ids: %{
          "google_places" => "test_place_123",
          "foursquare" => "test_fsq_456"
        }
      }

      {:ok, venue_input: venue_input}
    end

    test "returns empty list when no providers configured" do
      Repo.delete_all(GeocodingProvider)

      venue = %{
        name: "Test Venue",
        latitude: 40.7308,
        longitude: -74.0007,
        provider_ids: %{}
      }

      assert {:ok, [], metadata} = Orchestrator.fetch_venue_images(venue)
      assert metadata.providers_attempted == []
      assert metadata.total_images_found == 0
    end

    test "skips providers without place_id", %{venue_input: venue} do
      venue_no_ids = Map.put(venue, :provider_ids, %{})

      assert {:ok, images, metadata} = Orchestrator.fetch_venue_images(venue_no_ids)
      assert images == []
      assert metadata.providers_attempted == ["google_places", "foursquare"]
      assert metadata.providers_failed == ["google_places", "foursquare"]
    end

    test "aggregates results with proper metadata structure", %{venue_input: venue} do
      # Note: This test requires mocking provider responses in actual implementation
      # For now, we test the structure
      assert {:ok, _images, metadata} = Orchestrator.fetch_venue_images(venue)

      assert is_list(metadata.providers_attempted)
      assert is_list(metadata.providers_succeeded)
      assert is_list(metadata.providers_failed)
      assert is_map(metadata.cost_breakdown)
      assert is_map(metadata.requests_made)
      assert is_number(metadata.total_cost)
      assert is_integer(metadata.total_images_found)
      assert is_binary(metadata.fetched_at)
    end
  end

  describe "needs_enrichment?/2" do
    test "returns true when venue has never been enriched" do
      venue = %Venue{
        id: 1,
        venue_images: [],
        image_enrichment_metadata: nil
      }

      assert Orchestrator.needs_enrichment?(venue) == true
    end

    test "returns true when venue has no images and last check is stale (>7 days)" do
      stale_date = DateTime.utc_now() |> DateTime.add(-8, :day) |> DateTime.to_iso8601()

      venue = %Venue{
        id: 1,
        venue_images: [],
        image_enrichment_metadata: %{
          "last_checked_at" => stale_date
        }
      }

      assert Orchestrator.needs_enrichment?(venue) == true
    end

    test "returns true when images are stale (>90 days for venues with images)" do
      stale_date = DateTime.utc_now() |> DateTime.add(-91, :day) |> DateTime.to_iso8601()

      venue = %Venue{
        id: 1,
        venue_images: [%{"url" => "http://example.com/photo.jpg"}],
        image_enrichment_metadata: %{"last_checked_at" => stale_date}
      }

      assert Orchestrator.needs_enrichment?(venue) == true
    end

    test "returns false when images are fresh (<90 days for venues with images)" do
      fresh_date = DateTime.utc_now() |> DateTime.add(-15, :day) |> DateTime.to_iso8601()

      venue = %Venue{
        id: 1,
        venue_images: [%{"url" => "http://example.com/photo.jpg"}],
        image_enrichment_metadata: %{"last_checked_at" => fresh_date}
      }

      assert Orchestrator.needs_enrichment?(venue) == false
    end

    test "returns true when force flag is true" do
      fresh_date = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_iso8601()

      venue = %Venue{
        id: 1,
        venue_images: [%{"url" => "http://example.com/photo.jpg"}],
        image_enrichment_metadata: %{"last_checked_at" => fresh_date}
      }

      assert Orchestrator.needs_enrichment?(venue, true) == true
    end

    test "handles both atom and string keys in metadata" do
      # Atom keys
      venue_atom = %Venue{
        id: 1,
        venue_images: [],
        image_enrichment_metadata: %{last_checked_at: nil}
      }

      assert Orchestrator.needs_enrichment?(venue_atom) == true

      # String keys
      venue_string = %Venue{
        id: 1,
        venue_images: [],
        image_enrichment_metadata: %{"last_checked_at" => nil}
      }

      assert Orchestrator.needs_enrichment?(venue_string) == true
    end
  end

  describe "get_enabled_image_providers/0" do
    test "returns only active providers with image capability" do
      Repo.delete_all(GeocodingProvider)

      # Active with images
      active_images = %GeocodingProvider{
        name: "active_images",
        is_active: true,
        capabilities: %{"images" => true},
        priorities: %{"images" => 1}
      }

      # Inactive with images
      inactive_images = %GeocodingProvider{
        name: "inactive_images",
        is_active: false,
        capabilities: %{"images" => true},
        priorities: %{"images" => 2}
      }

      # Active without images
      active_no_images = %GeocodingProvider{
        name: "active_no_images",
        is_active: true,
        capabilities: %{"geocoding" => true},
        priorities: %{"geocoding" => 1}
      }

      Repo.insert!(active_images)
      Repo.insert!(inactive_images)
      Repo.insert!(active_no_images)

      providers = Orchestrator.get_enabled_image_providers()

      assert length(providers) == 1
      assert hd(providers).name == "active_images"
    end

    test "orders providers by image priority (lower = higher priority)" do
      Repo.delete_all(GeocodingProvider)

      low_priority = %GeocodingProvider{
        name: "low_priority",
        is_active: true,
        capabilities: %{"images" => true},
        priorities: %{"images" => 99}
      }

      high_priority = %GeocodingProvider{
        name: "high_priority",
        is_active: true,
        capabilities: %{"images" => true},
        priorities: %{"images" => 1}
      }

      medium_priority = %GeocodingProvider{
        name: "medium_priority",
        is_active: true,
        capabilities: %{"images" => true},
        priorities: %{"images" => 50}
      }

      Repo.insert!(low_priority)
      Repo.insert!(high_priority)
      Repo.insert!(medium_priority)

      providers = Orchestrator.get_enabled_image_providers()

      assert length(providers) == 3
      assert Enum.at(providers, 0).name == "high_priority"
      assert Enum.at(providers, 1).name == "medium_priority"
      assert Enum.at(providers, 2).name == "low_priority"
    end
  end
end
