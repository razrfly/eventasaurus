defmodule EventasaurusApp.Venues.VenueDeduplicationTest do
  use EventasaurusApp.DataCase
  import EventasaurusApp.Factory

  alias EventasaurusApp.Venues.VenueDeduplication

  describe "find_duplicates_for_city/2" do
    test "returns empty list when city_ids is empty" do
      assert VenueDeduplication.find_duplicates_for_city([]) == []
    end

    test "returns empty list when no venues exist in city" do
      city = insert(:city, %{name: "Empty City", slug: "empty-city"})
      assert VenueDeduplication.find_duplicates_for_city([city.id]) == []
    end

    test "returns empty list when venues are far apart" do
      city = insert(:city, %{name: "Test City", slug: "test-city-far"})

      # Venues 1km apart (well outside 500m default threshold)
      _venue1 =
        insert(:venue, %{
          name: "Venue North",
          city_id: city.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      _venue2 =
        insert(:venue, %{
          name: "Venue South",
          city_id: city.id,
          # ~1km south
          latitude: 50.0529,
          longitude: 19.9368
        })

      assert VenueDeduplication.find_duplicates_for_city([city.id]) == []
    end

    test "finds duplicate venues within distance threshold with similar names" do
      city = insert(:city, %{name: "Test City", slug: "test-city-dups"})

      # Venues ~50m apart with similar names (should pass 30% threshold at <50m)
      venue1 =
        insert(:venue, %{
          name: "Kino Pod Baranami",
          city_id: city.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      venue2 =
        insert(:venue, %{
          name: "Cinema Pod Baranami",
          city_id: city.id,
          # ~50m offset
          latitude: 50.06195,
          longitude: 19.9369
        })

      result = VenueDeduplication.find_duplicates_for_city([city.id])

      assert length(result) == 1
      group = hd(result)
      venue_ids = Enum.map(group.venues, & &1.id)
      assert venue1.id in venue_ids
      assert venue2.id in venue_ids
    end

    test "filters out pairs with low name similarity" do
      city = insert(:city, %{name: "Test City", slug: "test-city-lowsim"})

      # Venues ~40m apart but completely different names
      # Per new thresholds: <50m requires 30% similarity
      _venue1 =
        insert(:venue, %{
          name: "Theater ABC",
          city_id: city.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      _venue2 =
        insert(:venue, %{
          name: "Restaurant XYZ",
          city_id: city.id,
          # ~40m offset
          latitude: 50.06193,
          longitude: 19.93685
        })

      # These should NOT match because 0% similarity < 30% threshold
      result = VenueDeduplication.find_duplicates_for_city([city.id])
      assert result == []
    end

    test "respects city filtering" do
      city1 = insert(:city, %{name: "City One", slug: "city-one"})
      city2 = insert(:city, %{name: "City Two", slug: "city-two"})

      # Duplicates in city1
      _venue1 =
        insert(:venue, %{
          name: "Venue A",
          city_id: city1.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      _venue2 =
        insert(:venue, %{
          name: "Venue A Copy",
          city_id: city1.id,
          latitude: 50.06195,
          longitude: 19.9369
        })

      # Duplicates in city2
      _venue3 =
        insert(:venue, %{
          name: "Venue B",
          city_id: city2.id,
          latitude: 48.8566,
          longitude: 2.3522
        })

      _venue4 =
        insert(:venue, %{
          name: "Venue B Copy",
          city_id: city2.id,
          latitude: 48.85665,
          longitude: 2.35225
        })

      # Only find duplicates in city1
      result_city1 = VenueDeduplication.find_duplicates_for_city([city1.id])
      assert length(result_city1) == 1

      # Only find duplicates in city2
      result_city2 = VenueDeduplication.find_duplicates_for_city([city2.id])
      assert length(result_city2) == 1

      # Find duplicates in both cities
      result_both = VenueDeduplication.find_duplicates_for_city([city1.id, city2.id])
      assert length(result_both) == 2
    end

    test "groups connected duplicates into clusters" do
      city = insert(:city, %{name: "Test City", slug: "test-city-cluster"})

      # Create 3 venues that form a chain: A-B-C with similar names
      venue_a =
        insert(:venue, %{
          name: "Gwarek Club",
          city_id: city.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      venue_b =
        insert(:venue, %{
          name: "Klub Gwarek",
          city_id: city.id,
          # ~30m from A
          latitude: 50.06193,
          longitude: 19.93685
        })

      venue_c =
        insert(:venue, %{
          name: "Gwarek",
          city_id: city.id,
          # ~30m from B
          latitude: 50.06196,
          longitude: 19.9369
        })

      result = VenueDeduplication.find_duplicates_for_city([city.id])

      # All should be in one group (connected through B)
      assert length(result) == 1
      group = hd(result)
      venue_ids = Enum.map(group.venues, & &1.id)
      assert venue_a.id in venue_ids
      assert venue_b.id in venue_ids
      assert venue_c.id in venue_ids
    end

    test "sorts results by confidence descending" do
      city = insert(:city, %{name: "Test City", slug: "test-city-sort"})

      # Group 1: very close with similar names (high confidence)
      _g1_v1 =
        insert(:venue, %{
          name: "Close Cinema A",
          city_id: city.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      _g1_v2 =
        insert(:venue, %{
          name: "Close Cinema B",
          city_id: city.id,
          # ~10m
          latitude: 50.0619,
          longitude: 19.93681
        })

      # Group 2: further apart (lower confidence)
      _g2_v1 =
        insert(:venue, %{
          name: "Far Theater A",
          city_id: city.id,
          latitude: 48.8566,
          longitude: 2.3522
        })

      _g2_v2 =
        insert(:venue, %{
          name: "Far Theater B",
          city_id: city.id,
          # ~100m
          latitude: 48.8575,
          longitude: 2.3530
        })

      result = VenueDeduplication.find_duplicates_for_city([city.id])

      # Should have 2 groups sorted by confidence
      assert length(result) == 2
      confidences = Enum.map(result, & &1.confidence)
      assert confidences == Enum.sort(confidences, :desc)
    end

    test "respects limit option" do
      city = insert(:city, %{name: "Test City", slug: "test-city-limit"})

      # Create multiple duplicate pairs with similar names
      for i <- 1..5 do
        base_lat = 50.0 + i * 0.01

        insert(:venue, %{
          name: "Theater #{i}",
          city_id: city.id,
          latitude: base_lat,
          longitude: 19.9368
        })

        insert(:venue, %{
          name: "Theater #{i} Copy",
          city_id: city.id,
          latitude: base_lat + 0.0001,
          longitude: 19.93685
        })
      end

      result = VenueDeduplication.find_duplicates_for_city([city.id], limit: 2)
      assert length(result) == 2
    end
  end

  describe "find_duplicate_pairs/2" do
    test "returns empty list when city_ids is empty" do
      assert VenueDeduplication.find_duplicate_pairs([]) == []
    end

    test "returns empty list when no venues exist in city" do
      city = insert(:city, %{name: "Empty City", slug: "empty-city-pairs"})
      assert VenueDeduplication.find_duplicate_pairs([city.id]) == []
    end

    test "returns pairs directly without transitive grouping" do
      city = insert(:city, %{name: "Test City", slug: "test-city-pairs"})

      # Create a chain: A similar to B, B similar to C
      # Pair-based should return A-B and B-C separately (not grouped as A-B-C)
      venue_a =
        insert(:venue, %{
          name: "Gwarek Club",
          city_id: city.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      venue_b =
        insert(:venue, %{
          name: "Klub Gwarek",
          city_id: city.id,
          latitude: 50.06193,
          longitude: 19.93685
        })

      venue_c =
        insert(:venue, %{
          name: "Gwarek",
          city_id: city.id,
          latitude: 50.06196,
          longitude: 19.9369
        })

      result = VenueDeduplication.find_duplicate_pairs([city.id])

      # Should have multiple pairs (A-B, B-C, maybe A-C)
      assert length(result) >= 2

      # Each result should have venue_a and venue_b (not a venues array)
      first_pair = hd(result)
      assert Map.has_key?(first_pair, :venue_a)
      assert Map.has_key?(first_pair, :venue_b)
      assert Map.has_key?(first_pair, :similarity)
      assert Map.has_key?(first_pair, :distance)
      assert Map.has_key?(first_pair, :confidence)

      # Verify the venues are among our created venues
      venue_ids = [venue_a.id, venue_b.id, venue_c.id]
      assert first_pair.venue_a.id in venue_ids
      assert first_pair.venue_b.id in venue_ids
    end

    test "includes event counts in enriched pairs" do
      city = insert(:city, %{name: "Test City", slug: "test-city-events"})

      venue1 =
        insert(:venue, %{
          name: "Theater A",
          city_id: city.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      venue2 =
        insert(:venue, %{
          name: "Theater A Copy",
          city_id: city.id,
          latitude: 50.06195,
          longitude: 19.9369
        })

      # Add some events to each venue (use venue: instead of venue_id:)
      insert(:event, venue: venue1)
      insert(:event, venue: venue1)
      insert(:event, venue: venue2)

      result = VenueDeduplication.find_duplicate_pairs([city.id])

      assert length(result) == 1
      pair = hd(result)

      # Check event counts are present
      assert Map.has_key?(pair, :event_count_a)
      assert Map.has_key?(pair, :event_count_b)
      assert pair.event_count_a + pair.event_count_b >= 3
    end

    test "calculates confidence based on similarity and distance" do
      city = insert(:city, %{name: "Test City", slug: "test-city-conf"})

      # High confidence pair: very close with similar names
      insert(:venue, %{
        name: "Test Venue",
        city_id: city.id,
        latitude: 50.0619,
        longitude: 19.9368
      })

      insert(:venue, %{
        name: "Test Venue Copy",
        city_id: city.id,
        # ~10m
        latitude: 50.0619,
        longitude: 19.93681
      })

      result = VenueDeduplication.find_duplicate_pairs([city.id])

      assert length(result) == 1
      pair = hd(result)

      # High confidence for close venues with similar names
      assert pair.confidence >= 0.7
      assert pair.confidence <= 1.0
    end

    test "sorts pairs by confidence descending" do
      city = insert(:city, %{name: "Test City", slug: "test-city-sort-pairs"})

      # High confidence pair
      insert(:venue, %{
        name: "Close A",
        city_id: city.id,
        latitude: 50.0619,
        longitude: 19.9368
      })

      insert(:venue, %{
        name: "Close A Copy",
        city_id: city.id,
        latitude: 50.0619,
        longitude: 19.93681
      })

      # Lower confidence pair (further apart)
      insert(:venue, %{
        name: "Far B",
        city_id: city.id,
        latitude: 48.8566,
        longitude: 2.3522
      })

      insert(:venue, %{
        name: "Far B Copy",
        city_id: city.id,
        latitude: 48.858,
        longitude: 2.353
      })

      result = VenueDeduplication.find_duplicate_pairs([city.id])

      assert length(result) >= 2
      confidences = Enum.map(result, & &1.confidence)
      assert confidences == Enum.sort(confidences, :desc)
    end

    test "respects limit option" do
      city = insert(:city, %{name: "Test City", slug: "test-city-limit-pairs"})

      for i <- 1..5 do
        base_lat = 50.0 + i * 0.01

        insert(:venue, %{
          name: "Theater #{i}",
          city_id: city.id,
          latitude: base_lat,
          longitude: 19.9368
        })

        insert(:venue, %{
          name: "Theater #{i} Copy",
          city_id: city.id,
          latitude: base_lat + 0.0001,
          longitude: 19.93685
        })
      end

      result = VenueDeduplication.find_duplicate_pairs([city.id], limit: 2)
      assert length(result) == 2
    end
  end

  describe "calculate_duplicate_metrics/2" do
    test "returns appropriate defaults when city_ids is empty" do
      metrics = VenueDeduplication.calculate_duplicate_metrics([])

      assert metrics.pair_count == 0
      assert metrics.unique_venue_count == 0
      assert metrics.affected_events == 0
      assert metrics.high_confidence_count == 0
      assert metrics.medium_confidence_count == 0
      assert metrics.low_confidence_count == 0
      assert metrics.severity == :healthy
      assert metrics.duplicate_pairs == []

      # Legacy fields for backwards compatibility
      assert metrics.duplicate_count == 0
      assert metrics.duplicate_groups_count == 0
    end

    test "returns correct counts when no duplicates exist" do
      city = insert(:city, %{name: "Clean City", slug: "clean-city-metrics"})

      # Add some venues that aren't duplicates (far apart)
      insert(:venue, %{name: "Venue 1", city_id: city.id, latitude: 50.0, longitude: 19.0})
      insert(:venue, %{name: "Venue 2", city_id: city.id, latitude: 51.0, longitude: 20.0})

      metrics = VenueDeduplication.calculate_duplicate_metrics([city.id])

      assert metrics.pair_count == 0
      assert metrics.unique_venue_count == 0
      assert metrics.severity == :healthy
    end

    test "calculates correct counts for duplicate pairs" do
      city = insert(:city, %{name: "Test City", slug: "test-city-metrics-new"})

      # Create a duplicate pair
      insert(:venue, %{
        name: "Dup Venue A",
        city_id: city.id,
        latitude: 50.0619,
        longitude: 19.9368
      })

      insert(:venue, %{
        name: "Dup Venue A Copy",
        city_id: city.id,
        latitude: 50.06195,
        longitude: 19.9369
      })

      metrics = VenueDeduplication.calculate_duplicate_metrics([city.id])

      assert metrics.pair_count == 1
      assert metrics.unique_venue_count == 2
      assert length(metrics.duplicate_pairs) == 1

      # Legacy fields
      assert metrics.duplicate_count == 2
      assert metrics.duplicate_groups_count == 1
    end

    test "calculates severity as warning for moderate duplicates" do
      city = insert(:city, %{name: "Test City", slug: "test-city-warning-new"})

      # Create 3 duplicate pairs with identical names (high confidence - ~10m apart with 100% similarity)
      # High confidence requires: similarity * 0.7 + distance_weight * 0.3 >= 0.8
      # At ~10m: distance_weight = 1.0, so similarity >= (0.8 - 0.3) / 0.7 = 0.71
      # Using identical names gives 100% similarity
      for i <- 1..3 do
        base_lat = 50.0 + i * 0.01

        insert(:venue, %{
          name: "Identical Venue #{i}",
          city_id: city.id,
          latitude: base_lat,
          longitude: 19.9368
        })

        insert(:venue, %{
          name: "Identical Venue #{i}",
          city_id: city.id,
          latitude: base_lat + 0.0001,
          longitude: 19.93685
        })
      end

      metrics = VenueDeduplication.calculate_duplicate_metrics([city.id])

      assert metrics.pair_count == 3
      assert metrics.unique_venue_count == 6
      # With 3 high-confidence pairs (>= 2), severity should be warning
      assert metrics.high_confidence_count >= 2
      assert metrics.severity == :warning
    end

    test "categorizes confidence levels correctly" do
      city = insert(:city, %{name: "Test City", slug: "test-city-confidence-new"})

      # Very close pair (high confidence) - ~10m apart
      insert(:venue, %{
        name: "High A",
        city_id: city.id,
        latitude: 50.0619,
        longitude: 19.9368
      })

      insert(:venue, %{
        name: "High A Copy",
        city_id: city.id,
        latitude: 50.0619,
        longitude: 19.93681
      })

      # Further pair - ~200m apart (should be lower confidence)
      insert(:venue, %{
        name: "Med B",
        city_id: city.id,
        latitude: 48.8566,
        longitude: 2.3522
      })

      insert(:venue, %{
        name: "Med B Copy",
        city_id: city.id,
        # ~200m away
        latitude: 48.858,
        longitude: 2.354
      })

      metrics = VenueDeduplication.calculate_duplicate_metrics([city.id])

      # Should have at least 1 pair
      assert metrics.pair_count >= 1

      total_confidence_count =
        metrics.high_confidence_count + metrics.medium_confidence_count +
          metrics.low_confidence_count

      assert total_confidence_count == metrics.pair_count
    end

    test "includes affected events count" do
      city = insert(:city, %{name: "Test City", slug: "test-city-affected"})

      venue1 =
        insert(:venue, %{
          name: "Event Venue A",
          city_id: city.id,
          latitude: 50.0619,
          longitude: 19.9368
        })

      venue2 =
        insert(:venue, %{
          name: "Event Venue A Copy",
          city_id: city.id,
          latitude: 50.06195,
          longitude: 19.9369
        })

      # Add events (use venue: instead of venue_id:)
      insert(:event, venue: venue1)
      insert(:event, venue: venue1)
      insert(:event, venue: venue2)

      metrics = VenueDeduplication.calculate_duplicate_metrics([city.id])

      assert metrics.affected_events >= 3
    end
  end
end
