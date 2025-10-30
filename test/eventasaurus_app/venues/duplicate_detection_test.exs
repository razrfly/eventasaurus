defmodule EventasaurusApp.Venues.DuplicateDetectionTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Venues.DuplicateDetection
  alias EventasaurusApp.Venues
  alias EventasaurusDiscovery.Locations.City

  @moduletag :duplicate_detection

  describe "distance-based similarity thresholds" do
    test "same coordinates (0m) requires 0.0 similarity" do
      assert DuplicateDetection.get_similarity_threshold_for_distance(0) == 0.0
    end

    test "within 50m requires 0.0 similarity" do
      assert DuplicateDetection.get_similarity_threshold_for_distance(25) == 0.0
      assert DuplicateDetection.get_similarity_threshold_for_distance(49) == 0.0
    end

    test "50-100m requires 0.3 similarity" do
      assert DuplicateDetection.get_similarity_threshold_for_distance(50) == 0.3
      assert DuplicateDetection.get_similarity_threshold_for_distance(75) == 0.3
      assert DuplicateDetection.get_similarity_threshold_for_distance(99) == 0.3
    end

    test "100-200m requires 0.6 similarity" do
      assert DuplicateDetection.get_similarity_threshold_for_distance(100) == 0.6
      assert DuplicateDetection.get_similarity_threshold_for_distance(150) == 0.6
      assert DuplicateDetection.get_similarity_threshold_for_distance(199) == 0.6
    end

    test ">200m requires 0.8 similarity" do
      assert DuplicateDetection.get_similarity_threshold_for_distance(200) == 0.8
      assert DuplicateDetection.get_similarity_threshold_for_distance(500) == 0.8
      assert DuplicateDetection.get_similarity_threshold_for_distance(1000) == 0.8
    end
  end

  describe "find_duplicate/1" do
    setup do
      # Create test city
      {:ok, country} =
        EventasaurusDiscovery.Locations.Country.changeset(
          %EventasaurusDiscovery.Locations.Country{},
          %{
            name: "Poland",
            code: "PL"
          }
        )
        |> Repo.insert()

      {:ok, city} =
        City.changeset(%City{}, %{
          name: "Warsaw",
          country_id: country.id,
          latitude: 52.2297,
          longitude: 21.0122
        })
        |> Repo.insert()

      %{city_id: city.id}
    end

    test "finds exact match at same coordinates with different names", %{city_id: city_id} do
      # Create original venue
      {:ok, original} =
        Venues.create_venue(%{
          name: "Piętro Niżej",
          latitude: 52.2363,
          longitude: 21.00642,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      # Try to find duplicate with UI text suffix
      result =
        DuplicateDetection.find_duplicate(%{
          latitude: 52.2363,
          longitude: 21.00642,
          name: "Piętro Niżej (pokaż na mapie)",
          city_id: city_id
        })

      assert result != nil
      assert result.id == original.id
      # At 0 meters, any similarity should match (threshold is 0.0)
      assert result.distance < 1.0
    end

    test "finds match within 50m with low similarity", %{city_id: city_id} do
      # Create original venue
      {:ok, original} =
        Venues.create_venue(%{
          name: "La Lucy",
          latitude: 52.1,
          longitude: 21.2,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      # Try to find venue with very different name but within 50m
      # Move ~30m east (at lat 52, 1 degree lng ≈ 69km, so 30m ≈ 0.00043 degrees)
      result =
        DuplicateDetection.find_duplicate(%{
          latitude: 52.1,
          longitude: 21.20043,
          name: "ul. Marszałkowska 10",
          city_id: city_id
        })

      assert result != nil
      assert result.id == original.id
      # Within 50m, 0.0 similarity required
      assert result.distance < 50.0
    end

    test "finds match at 75m with 0.3 similarity", %{city_id: city_id} do
      # Create original venue
      {:ok, original} =
        Venues.create_venue(%{
          name: "Red Lion Pub",
          latitude: 52.1,
          longitude: 21.2,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      # Try to find venue ~75m away with moderate similarity
      # Move ~75m east (≈ 0.00109 degrees longitude)
      result =
        DuplicateDetection.find_duplicate(%{
          latitude: 52.1,
          longitude: 21.20109,
          name: "Red Lion",
          city_id: city_id
        })

      assert result != nil
      assert result.id == original.id
      assert result.distance >= 50.0
      assert result.distance < 100.0
    end

    test "does NOT find match at 75m with 0.2 similarity", %{city_id: city_id} do
      # Create original venue
      {:ok, _original} =
        Venues.create_venue(%{
          name: "Red Lion Pub",
          latitude: 52.1,
          longitude: 21.2,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      # Try to find venue ~75m away with very low similarity
      # At 75m, requires 0.3 similarity, but "Red Lion Pub" vs "Completely Different" has ~0.1
      result =
        DuplicateDetection.find_duplicate(%{
          latitude: 52.1,
          longitude: 21.20109,
          name: "Completely Different Venue Name",
          city_id: city_id
        })

      assert result == nil
    end

    test "finds match at 150m with 0.6 similarity", %{city_id: city_id} do
      # Create original venue
      {:ok, original} =
        Venues.create_venue(%{
          name: "Warsaw Cinema Palace",
          latitude: 52.1,
          longitude: 21.2,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      # Try to find venue ~150m away with good similarity
      # Move ~150m east (≈ 0.00217 degrees longitude)
      result =
        DuplicateDetection.find_duplicate(%{
          latitude: 52.1,
          longitude: 21.20217,
          name: "Cinema Palace Warsaw",
          city_id: city_id
        })

      assert result != nil
      assert result.id == original.id
      assert result.distance >= 100.0
      assert result.distance < 200.0
    end

    test "does NOT find match at 150m with 0.5 similarity", %{city_id: city_id} do
      # Create original venue
      {:ok, _original} =
        Venues.create_venue(%{
          name: "Warsaw Cinema Palace",
          latitude: 52.1,
          longitude: 21.2,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      # Try to find venue ~150m away with medium similarity (below 0.6 threshold)
      result =
        DuplicateDetection.find_duplicate(%{
          latitude: 52.1,
          longitude: 21.20217,
          name: "Cinema Hall",
          city_id: city_id
        })

      assert result == nil
    end

    test "returns nil when no venues nearby", %{city_id: city_id} do
      result =
        DuplicateDetection.find_duplicate(%{
          latitude: 52.5,
          longitude: 21.5,
          name: "Isolated Venue",
          city_id: city_id
        })

      assert result == nil
    end

    test "returns nil when coordinates missing" do
      result =
        DuplicateDetection.find_duplicate(%{
          name: "Test Venue"
        })

      assert result == nil
    end
  end

  describe "check_duplicate/1" do
    setup do
      # Create test city
      {:ok, country} =
        EventasaurusDiscovery.Locations.Country.changeset(
          %EventasaurusDiscovery.Locations.Country{},
          %{
            name: "Poland",
            code: "PL"
          }
        )
        |> Repo.insert()

      {:ok, city} =
        City.changeset(%City{}, %{
          name: "Warsaw",
          country_id: country.id,
          latitude: 52.2297,
          longitude: 21.0122
        })
        |> Repo.insert()

      %{city_id: city.id}
    end

    test "returns {:ok, nil} when no duplicate found", %{city_id: city_id} do
      result =
        DuplicateDetection.check_duplicate(%{
          latitude: 52.5,
          longitude: 21.5,
          name: "Unique Venue",
          city_id: city_id
        })

      assert result == {:ok, nil}
    end

    test "returns {:error, reason, opts} when duplicate found", %{city_id: city_id} do
      # Create original venue
      {:ok, original} =
        Venues.create_venue(%{
          name: "Piętro Niżej",
          latitude: 52.2363,
          longitude: 21.00642,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      # Check for duplicate
      result =
        DuplicateDetection.check_duplicate(%{
          latitude: 52.2363,
          longitude: 21.00642,
          name: "Piętro Niżej (pokaż na mapie)",
          city_id: city_id
        })

      assert {:error, reason, opts} = result
      assert reason =~ "Duplicate venue found"
      assert reason =~ "Piętro Niżej"
      assert opts[:existing_id] == original.id
      assert opts[:distance] < 1.0
    end
  end

  describe "find_nearby_venues_postgis/4" do
    setup do
      # Create test city
      {:ok, country} =
        EventasaurusDiscovery.Locations.Country.changeset(
          %EventasaurusDiscovery.Locations.Country{},
          %{
            name: "Poland",
            code: "PL"
          }
        )
        |> Repo.insert()

      {:ok, city} =
        City.changeset(%City{}, %{
          name: "Warsaw",
          country_id: country.id,
          latitude: 52.2297,
          longitude: 21.0122
        })
        |> Repo.insert()

      %{city_id: city.id}
    end

    test "finds venues within specified radius", %{city_id: city_id} do
      # Create venues at different distances
      {:ok, v1} =
        Venues.create_venue(%{
          name: "Very Close",
          latitude: 52.1,
          longitude: 21.2,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      {:ok, v2} =
        Venues.create_venue(%{
          name: "Medium Distance",
          latitude: 52.1,
          longitude: 21.20109,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      {:ok, _v3} =
        Venues.create_venue(%{
          name: "Far Away",
          latitude: 52.1,
          longitude: 21.25,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      # Search within 100m of first venue
      results = DuplicateDetection.find_nearby_venues_postgis(52.1, 21.2, city_id, 100)

      # Should find v1 (0m) and v2 (~75m), but not v3 (~3.5km)
      assert length(results) == 2
      assert Enum.any?(results, fn v -> v.id == v1.id end)
      assert Enum.any?(results, fn v -> v.id == v2.id end)

      # Results should be ordered by distance
      assert hd(results).id == v1.id
    end

    test "returns empty list when no venues nearby", %{city_id: city_id} do
      results = DuplicateDetection.find_nearby_venues_postgis(52.5, 21.5, city_id, 100)

      assert results == []
    end

    test "includes distance field in results", %{city_id: city_id} do
      {:ok, _v1} =
        Venues.create_venue(%{
          name: "Test Venue",
          latitude: 52.1,
          longitude: 21.2,
          city_id: city_id,
          venue_type: "venue",
          source: "scraper"
        })

      results = DuplicateDetection.find_nearby_venues_postgis(52.1, 21.2, city_id, 100)

      assert length(results) == 1
      result = hd(results)
      assert Map.has_key?(result, :distance)
      assert result.distance < 1.0
    end
  end

  describe "calculate_name_similarity/2" do
    test "identical names return 1.0" do
      similarity = DuplicateDetection.calculate_name_similarity("Red Lion", "Red Lion")
      assert similarity == 1.0
    end

    test "similar names return high similarity" do
      similarity = DuplicateDetection.calculate_name_similarity("Red Lion Pub", "Red Lion")
      # PostgreSQL trigram similarity can vary slightly based on version
      assert similarity > 0.65
      assert similarity < 1.0
    end

    test "different names return low similarity" do
      similarity =
        DuplicateDetection.calculate_name_similarity("Red Lion", "Completely Different")

      assert similarity < 0.3
    end

    test "handles Polish characters" do
      similarity = DuplicateDetection.calculate_name_similarity("Piętro Niżej", "Piętro Niżej")
      assert similarity == 1.0
    end

    test "handles UI text suffixes" do
      similarity =
        DuplicateDetection.calculate_name_similarity(
          "Piętro Niżej",
          "Piętro Niżej (pokaż na mapie)"
        )

      # Should have moderate similarity (the base name matches)
      assert similarity > 0.4
      assert similarity < 0.8
    end
  end
end
