defmodule EventasaurusDiscovery.Geocoding.MetadataBuilderTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Geocoding.MetadataBuilder

  describe "build_openstreetmap_metadata/1" do
    test "creates OSM metadata with correct structure" do
      metadata = MetadataBuilder.build_openstreetmap_metadata("123 Main St, London")

      assert metadata.provider == "openstreetmap"
      assert metadata.cost_per_call == 0.0
      assert metadata.original_address == "123 Main St, London"
      assert metadata.fallback_used == false
      assert metadata.geocoding_failed == false
      assert %DateTime{} = metadata.geocoded_at
    end
  end

  describe "build_google_maps_metadata/2" do
    test "creates Google Maps metadata with correct structure" do
      metadata = MetadataBuilder.build_google_maps_metadata("123 Main St, London", 3)

      assert metadata.provider == "google_maps"
      assert metadata.cost_per_call == 0.005
      assert metadata.original_address == "123 Main St, London"
      assert metadata.fallback_used == true
      assert metadata.geocoding_attempts == 3
      assert metadata.geocoding_failed == false
      assert %DateTime{} = metadata.geocoded_at
    end

    test "defaults to 1 attempt when not specified" do
      metadata = MetadataBuilder.build_google_maps_metadata("Test Address")

      assert metadata.geocoding_attempts == 1
    end
  end

  describe "build_google_places_metadata/1" do
    test "creates Google Places metadata with correct structure" do
      google_response = %{
        "place_id" => "ChIJ123",
        "formatted_address" => "123 Main St, London",
        "geometry" => %{"location" => %{"lat" => 51.5074, "lng" => -0.1278}}
      }

      metadata = MetadataBuilder.build_google_places_metadata(google_response)

      assert metadata.provider == "google_places"
      assert metadata.cost_per_call == 0.037
      assert metadata.google_places_response == google_response
      assert metadata.geocoding_failed == false
      assert %DateTime{} = metadata.geocoded_at
    end
  end

  describe "build_provided_coordinates_metadata/0" do
    test "creates metadata for directly provided coordinates" do
      metadata = MetadataBuilder.build_provided_coordinates_metadata()

      assert metadata.provider == "provided"
      assert metadata.cost_per_call == 0.0
      assert metadata.geocoding_failed == false
      assert %DateTime{} = metadata.geocoded_at
    end
  end

  describe "build_city_resolver_metadata/0" do
    test "creates metadata for offline CityResolver geocoding" do
      metadata = MetadataBuilder.build_city_resolver_metadata()

      assert metadata.provider == "city_resolver_offline"
      assert metadata.cost_per_call == 0.0
      assert metadata.geocoding_failed == false
      assert %DateTime{} = metadata.geocoded_at
    end
  end

  describe "build_deferred_geocoding_metadata/0" do
    test "creates metadata for deferred geocoding" do
      metadata = MetadataBuilder.build_deferred_geocoding_metadata()

      assert metadata.provider == "deferred"
      assert metadata.needs_manual_geocoding == true
      assert metadata.cost_per_call == 0.0
      assert metadata.geocoding_failed == false
      assert %DateTime{} = metadata.geocoded_at
    end
  end

  describe "add_scraper_source/2" do
    test "adds scraper source to metadata" do
      metadata = MetadataBuilder.build_openstreetmap_metadata("Test Address")
      updated = MetadataBuilder.add_scraper_source(metadata, "question_one")

      assert updated.source_scraper == "question_one"
      # Verify other fields are preserved
      assert updated.provider == "openstreetmap"
      assert updated.cost_per_call == 0.0
    end
  end

  describe "mark_failed/2" do
    test "marks metadata as failed with reason" do
      metadata = MetadataBuilder.build_google_maps_metadata("Invalid Address", 3)
      failed = MetadataBuilder.mark_failed(metadata, :geocoding_timeout)

      assert failed.geocoding_failed == true
      assert failed.failure_reason == "geocoding_timeout"
      # Verify other fields are preserved
      assert failed.provider == "google_maps"
      assert failed.cost_per_call == 0.005
    end

    test "converts atom reason to string" do
      metadata = MetadataBuilder.build_openstreetmap_metadata("Test")
      failed = MetadataBuilder.mark_failed(metadata, :osm_rate_limited)

      assert failed.failure_reason == "osm_rate_limited"
    end
  end

  describe "resolve_deferred_geocoding/2" do
    test "updates deferred metadata with actual geocoding data" do
      deferred = MetadataBuilder.build_deferred_geocoding_metadata()
      # Simulate some time passing
      Process.sleep(10)

      actual =
        MetadataBuilder.build_google_places_metadata(%{"place_id" => "ChIJ123"})
        |> MetadataBuilder.add_scraper_source("karnet")

      resolved = MetadataBuilder.resolve_deferred_geocoding(deferred, actual)

      assert resolved.provider == "google_places"
      assert resolved.needs_manual_geocoding == false
      assert resolved.originally_deferred == true
      assert resolved.deferred_at == deferred.geocoded_at
      assert resolved.source_scraper == "karnet"
    end
  end

  describe "validate/1" do
    test "validates complete metadata successfully" do
      metadata = MetadataBuilder.build_openstreetmap_metadata("Test Address")

      assert {:ok, ^metadata} = MetadataBuilder.validate(metadata)
    end

    test "returns error for missing required fields" do
      incomplete_metadata = %{provider: "test"}

      assert {:error, message} = MetadataBuilder.validate(incomplete_metadata)
      assert message =~ "Missing required fields"
      assert message =~ "cost_per_call"
      assert message =~ "geocoded_at"
      assert message =~ "geocoding_failed"
    end
  end

  describe "summary/1" do
    test "generates concise summary string" do
      metadata =
        MetadataBuilder.build_google_places_metadata(%{"place_id" => "ChIJ123"})
        |> MetadataBuilder.add_scraper_source("kino_krakow")

      summary = MetadataBuilder.summary(metadata)

      assert summary =~ "provider=google_places"
      assert summary =~ "cost=$0.037"
      assert summary =~ "failed=false"
      assert summary =~ "scraper=kino_krakow"
    end

    test "handles metadata without scraper" do
      metadata = MetadataBuilder.build_city_resolver_metadata()

      summary = MetadataBuilder.summary(metadata)

      assert summary =~ "provider=city_resolver_offline"
      assert summary =~ "cost=$0.0"
      refute summary =~ "scraper="
    end
  end

  describe "integration - full workflow" do
    test "OSM success scenario" do
      metadata =
        MetadataBuilder.build_openstreetmap_metadata("123 Main St, London")
        |> MetadataBuilder.add_scraper_source("question_one")

      assert metadata.provider == "openstreetmap"
      assert metadata.cost_per_call == 0.0
      assert metadata.source_scraper == "question_one"
      assert metadata.geocoding_failed == false
      assert {:ok, _} = MetadataBuilder.validate(metadata)
    end

    test "Google Maps fallback scenario" do
      metadata =
        MetadataBuilder.build_google_maps_metadata("123 Main St, London", 3)
        |> MetadataBuilder.add_scraper_source("question_one")

      assert metadata.provider == "google_maps"
      assert metadata.cost_per_call == 0.005
      assert metadata.fallback_used == true
      assert metadata.geocoding_attempts == 3
      assert metadata.source_scraper == "question_one"
      assert {:ok, _} = MetadataBuilder.validate(metadata)
    end

    test "Google Places scenario" do
      google_response = %{"place_id" => "ChIJ123", "name" => "Test Venue"}

      metadata =
        MetadataBuilder.build_google_places_metadata(google_response)
        |> MetadataBuilder.add_scraper_source("kino_krakow")

      assert metadata.provider == "google_places"
      assert metadata.cost_per_call == 0.037
      assert metadata.source_scraper == "kino_krakow"
      assert {:ok, _} = MetadataBuilder.validate(metadata)
    end

    test "failed geocoding scenario" do
      metadata =
        MetadataBuilder.build_google_maps_metadata("Invalid Address", 3)
        |> MetadataBuilder.add_scraper_source("question_one")
        |> MetadataBuilder.mark_failed(:all_geocoding_failed)

      assert metadata.geocoding_failed == true
      assert metadata.failure_reason == "all_geocoding_failed"
      assert metadata.cost_per_call == 0.005
      assert {:ok, _} = MetadataBuilder.validate(metadata)
    end
  end
end
