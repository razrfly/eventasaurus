defmodule EventasaurusDiscovery.Locations.CityHierarchyTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Locations.{City, CityHierarchy}
  alias EventasaurusDiscovery.Locations.Country

  describe "haversine_distance/4" do
    test "calculates distance between Paris and La Défense (~5km)" do
      # Paris center: 48.8566, 2.3522
      # La Défense: 48.8738, 2.2950
      distance = CityHierarchy.haversine_distance(48.8566, 2.3522, 48.8738, 2.2950)

      # Should be approximately 4.87 km
      assert_in_delta distance, 4.87, 0.5
    end

    test "calculates distance between New York and Los Angeles (~3940km)" do
      # New York: 40.7128, -74.0060
      # Los Angeles: 34.0522, -118.2437
      distance = CityHierarchy.haversine_distance(40.7128, -74.0060, 34.0522, -118.2437)

      # Should be approximately 3944 km
      assert_in_delta distance, 3944, 50
    end

    test "handles Decimal coordinates" do
      lat1 = Decimal.new("48.8566")
      lon1 = Decimal.new("2.3522")
      lat2 = Decimal.new("48.8738")
      lon2 = Decimal.new("2.2950")

      distance = CityHierarchy.haversine_distance(lat1, lon1, lat2, lon2)

      assert_in_delta distance, 4.87, 0.5
    end

    test "returns 0 for same coordinates" do
      distance = CityHierarchy.haversine_distance(48.8566, 2.3522, 48.8566, 2.3522)

      assert_in_delta distance, 0.0, 0.01
    end
  end

  describe "cluster_nearby_cities/2" do
    setup do
      country = insert(:country, name: "France", code: "FR")

      # Create Paris metropolitan area cities
      paris = insert(:city, name: "Paris", latitude: 48.8566, longitude: 2.3522, country: country)

      paris_8 =
        insert(:city, name: "Paris 8", latitude: 48.8738, longitude: 2.3100, country: country)

      paris_16 =
        insert(:city, name: "Paris 16", latitude: 48.8643, longitude: 2.2750, country: country)

      # Create isolated city far away
      lyon = insert(:city, name: "Lyon", latitude: 45.7640, longitude: 4.8357, country: country)

      %{
        country: country,
        paris: paris,
        paris_8: paris_8,
        paris_16: paris_16,
        lyon: lyon
      }
    end

    test "clusters Paris cities together (within 20km)", %{
      paris: paris,
      paris_8: paris_8,
      paris_16: paris_16,
      lyon: lyon
    } do
      cities = [paris, paris_8, paris_16, lyon]

      clusters = CityHierarchy.cluster_nearby_cities(cities, 20.0)

      # Should have 2 clusters: Paris metro (3 cities) and Lyon (1 city)
      assert length(clusters) == 2

      # Find the Paris cluster (should have 3 cities)
      paris_cluster =
        Enum.find(clusters, fn cluster ->
          length(cluster) == 3
        end)

      assert paris_cluster != nil
      assert paris.id in paris_cluster
      assert paris_8.id in paris_cluster
      assert paris_16.id in paris_cluster

      # Find Lyon cluster (should be alone)
      lyon_cluster = Enum.find(clusters, fn cluster -> lyon.id in cluster end)
      assert length(lyon_cluster) == 1
    end

    test "uses stricter threshold to separate cities", %{
      paris: paris,
      paris_8: paris_8,
      paris_16: paris_16
    } do
      cities = [paris, paris_8, paris_16]

      # Use very small threshold (2km) - cities should not cluster
      clusters = CityHierarchy.cluster_nearby_cities(cities, 2.0)

      # Each city should be its own cluster
      assert length(clusters) == 3
    end

    test "respects country boundaries" do
      # Use unique codes to avoid conflicts with existing data
      france = insert(:country, name: "France Test", code: "F1")
      germany = insert(:country, name: "Germany Test", code: "D1")

      # Create two cities with same coordinates but different countries
      paris = insert(:city, name: "Paris", latitude: 48.8566, longitude: 2.3522, country: france)

      # Hypothetical "Paris" in Germany at same coordinates
      fake_paris =
        insert(:city, name: "Paris", latitude: 48.8566, longitude: 2.3522, country: germany)

      clusters = CityHierarchy.cluster_nearby_cities([paris, fake_paris], 20.0)

      # Should have 2 separate clusters despite same coordinates
      assert length(clusters) == 2
    end
  end

  describe "aggregate_stats_by_cluster/2" do
    setup do
      country = insert(:country, name: "France", code: "FR")

      paris = insert(:city, name: "Paris", latitude: 48.8566, longitude: 2.3522, country: country)

      paris_8 =
        insert(:city, name: "Paris 8", latitude: 48.8738, longitude: 2.3100, country: country)

      paris_16 =
        insert(:city, name: "Paris 16", latitude: 48.8643, longitude: 2.2750, country: country)

      lyon = insert(:city, name: "Lyon", latitude: 45.7640, longitude: 4.8357, country: country)

      %{
        paris: paris,
        paris_8: paris_8,
        paris_16: paris_16,
        lyon: lyon
      }
    end

    test "aggregates Paris cities with Paris as primary (most events)", %{
      paris: paris,
      paris_8: paris_8,
      paris_16: paris_16,
      lyon: lyon
    } do
      city_stats = [
        %{city_id: paris.id, city_name: "Paris", count: 302},
        %{city_id: paris_8.id, city_name: "Paris 8", count: 21},
        %{city_id: paris_16.id, city_name: "Paris 16", count: 21},
        %{city_id: lyon.id, city_name: "Lyon", count: 50}
      ]

      result = CityHierarchy.aggregate_stats_by_cluster(city_stats, 20.0)

      # Should have 2 aggregated entries
      assert length(result) == 2

      # Find Paris cluster
      paris_result = Enum.find(result, &(&1.city_id == paris.id))
      assert paris_result != nil
      assert paris_result.city_name == "Paris"
      # Total: 302 + 21 + 21 = 344
      assert paris_result.count == 344
      assert length(paris_result.subcities) == 2

      # Check subcities
      subcity_ids = Enum.map(paris_result.subcities, & &1.city_id)
      assert paris_8.id in subcity_ids
      assert paris_16.id in subcity_ids

      # Find Lyon (should be standalone)
      lyon_result = Enum.find(result, &(&1.city_id == lyon.id))
      assert lyon_result != nil
      assert lyon_result.count == 50
      assert lyon_result.subcities == []
    end

    test "handles tie in event counts with consistent selection", %{
      paris: paris,
      paris_8: paris_8
    } do
      # Both cities have same event count
      city_stats = [
        %{city_id: paris.id, city_name: "Paris", count: 50},
        %{city_id: paris_8.id, city_name: "Paris 8", count: 50}
      ]

      result = CityHierarchy.aggregate_stats_by_cluster(city_stats, 20.0)

      # Should have 1 cluster
      assert length(result) == 1

      cluster = List.first(result)
      # Total should be 100
      assert cluster.count == 100
      # One should be primary, one should be subcity
      assert length(cluster.subcities) == 1
    end

    test "sorts results by total count descending", %{
      paris: paris,
      paris_8: paris_8,
      lyon: lyon
    } do
      city_stats = [
        %{city_id: lyon.id, city_name: "Lyon", count: 500},
        %{city_id: paris.id, city_name: "Paris", count: 100},
        %{city_id: paris_8.id, city_name: "Paris 8", count: 50}
      ]

      result = CityHierarchy.aggregate_stats_by_cluster(city_stats, 20.0)

      # Lyon should be first (500 events)
      assert List.first(result).city_id == lyon.id
      assert List.first(result).count == 500

      # Paris cluster should be second (150 total)
      paris_cluster = Enum.find(result, &(&1.city_id == paris.id))
      assert paris_cluster.count == 150
    end

    test "handles empty stats list" do
      result = CityHierarchy.aggregate_stats_by_cluster([], 20.0)

      assert result == []
    end

    test "handles single city" do
      country = insert(:country)
      city = insert(:city, country: country)

      city_stats = [%{city_id: city.id, city_name: city.name, count: 100}]

      result = CityHierarchy.aggregate_stats_by_cluster(city_stats, 20.0)

      assert length(result) == 1
      assert List.first(result).city_id == city.id
      assert List.first(result).count == 100
      assert List.first(result).subcities == []
    end
  end

  describe "edge cases" do
    test "handles cities in a line (transitive clustering)" do
      country = insert(:country)

      # Create 3 cities in a line, each 15km apart
      # A -15km- B -15km- C
      # With 20km threshold, all should cluster together
      city_a =
        insert(:city, name: "City A", latitude: 48.8566, longitude: 2.0000, country: country)

      city_b =
        insert(:city, name: "City B", latitude: 48.8566, longitude: 2.1500, country: country)

      city_c =
        insert(:city, name: "City C", latitude: 48.8566, longitude: 2.3000, country: country)

      clusters = CityHierarchy.cluster_nearby_cities([city_a, city_b, city_c], 20.0)

      # All should be in one cluster due to transitivity
      assert length(clusters) == 1
      cluster = List.first(clusters)
      assert length(cluster) == 3
      assert city_a.id in cluster
      assert city_b.id in cluster
      assert city_c.id in cluster
    end

    test "handles cities forming a triangle" do
      country = insert(:country)

      # Create 3 cities in triangle, each ~10km apart
      city_a =
        insert(:city, name: "City A", latitude: 48.8566, longitude: 2.3522, country: country)

      city_b =
        insert(:city, name: "City B", latitude: 48.9566, longitude: 2.3522, country: country)

      city_c =
        insert(:city, name: "City C", latitude: 48.9066, longitude: 2.4522, country: country)

      clusters = CityHierarchy.cluster_nearby_cities([city_a, city_b, city_c], 20.0)

      # All should be in one cluster
      assert length(clusters) == 1
      assert length(List.first(clusters)) == 3
    end
  end
end
