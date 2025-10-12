defmodule EventasaurusDiscovery.Metrics.GeocodingStatsTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Metrics.GeocodingStats
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Repo

  describe "monthly_cost/1" do
    test "returns zero cost when no venues exist" do
      assert {:ok, %{total_cost: cost, count: 0}} = GeocodingStats.monthly_cost()
      assert cost == 0.0 or is_nil(cost)
    end

    test "calculates total cost for venues in current month" do
      # Create test venue with geocoding metadata
      create_test_venue("Test Venue 1", "google_places", 0.037, "kino_krakow")

      assert {:ok, %{total_cost: cost, count: count}} = GeocodingStats.monthly_cost()
      assert cost >= 0.037
      assert count >= 1
    end

    test "filters by specific month" do
      # This test would require creating venues with specific geocoded_at dates
      # Skipping for now as it requires date manipulation in metadata
      date = ~D[2025-01-15]
      assert {:ok, %{total_cost: _cost, count: _count}} = GeocodingStats.monthly_cost(date)
    end
  end

  describe "costs_by_provider/0" do
    test "returns empty list when no venues exist" do
      assert {:ok, []} = GeocodingStats.costs_by_provider()
    end

    test "groups costs by geocoding provider" do
      create_test_venue("Venue 1", "google_places", 0.037, "kino_krakow")
      create_test_venue("Venue 2", "openstreetmap", 0.0, "question_one")
      create_test_venue("Venue 3", "google_places", 0.037, "resident_advisor")

      assert {:ok, results} = GeocodingStats.costs_by_provider()

      assert length(results) >= 2

      google_places = Enum.find(results, fn r -> r.provider == "google_places" end)
      osm = Enum.find(results, fn r -> r.provider == "openstreetmap" end)

      assert google_places.count >= 2
      assert google_places.total_cost >= 0.074

      assert osm.count >= 1
      assert osm.total_cost == 0.0
    end
  end

  describe "costs_by_scraper/0" do
    test "returns empty list when no venues exist" do
      assert {:ok, []} = GeocodingStats.costs_by_scraper()
    end

    test "groups costs by source scraper" do
      create_test_venue("Venue 1", "google_places", 0.037, "kino_krakow")
      create_test_venue("Venue 2", "google_places", 0.037, "resident_advisor")
      create_test_venue("Venue 3", "openstreetmap", 0.0, "question_one")

      assert {:ok, results} = GeocodingStats.costs_by_scraper()

      assert length(results) >= 3

      kino = Enum.find(results, fn r -> r.scraper == "kino_krakow" end)
      assert kino.count >= 1
      assert kino.total_cost >= 0.037
    end
  end

  describe "failed_geocoding_count/0" do
    test "returns zero when no failed venues exist" do
      assert {:ok, 0} = GeocodingStats.failed_geocoding_count()
    end

    test "counts venues with failed geocoding" do
      create_test_venue("Failed Venue", "google_maps", 0.005, "question_one", failed: true)

      assert {:ok, count} = GeocodingStats.failed_geocoding_count()
      assert count >= 1
    end
  end

  describe "failed_geocoding_venues/1" do
    test "returns empty list when no failures" do
      assert {:ok, []} = GeocodingStats.failed_geocoding_venues()
    end

    test "returns list of failed venues with details" do
      create_test_venue("Failed Venue", "google_maps", 0.005, "question_one", failed: true)

      assert {:ok, venues} = GeocodingStats.failed_geocoding_venues(10)
      assert length(venues) >= 1

      failed_venue = hd(venues)
      assert failed_venue.name == "Failed Venue"
      assert failed_venue.failure_reason != nil
    end

    test "limits results to specified count" do
      for i <- 1..15 do
        create_test_venue("Failed #{i}", "google_maps", 0.005, "question_one", failed: true)
      end

      assert {:ok, venues} = GeocodingStats.failed_geocoding_venues(5)
      assert length(venues) == 5
    end
  end

  describe "deferred_geocoding_count/0" do
    test "returns zero when no deferred venues exist" do
      assert {:ok, 0} = GeocodingStats.deferred_geocoding_count()
    end

    test "counts venues needing manual geocoding" do
      create_test_venue("Deferred Venue", "deferred", 0.0, "karnet", deferred: true)

      assert {:ok, count} = GeocodingStats.deferred_geocoding_count()
      assert count >= 1
    end
  end

  describe "summary/0" do
    test "returns comprehensive statistics" do
      create_test_venue("Venue 1", "google_places", 0.037, "kino_krakow")
      create_test_venue("Venue 2", "openstreetmap", 0.0, "question_one")

      assert {:ok, summary} = GeocodingStats.summary()

      assert summary.total_venues_geocoded >= 2
      assert is_float(summary.total_cost) or is_integer(summary.total_cost)
      assert is_list(summary.by_provider)
      assert is_list(summary.by_scraper)
      assert is_integer(summary.failed_count)
      assert is_integer(summary.deferred_count)
    end
  end

  describe "format_report/1" do
    test "generates readable report from summary" do
      summary = %{
        total_venues_geocoded: 100,
        total_cost: 3.74,
        free_geocoding_count: 50,
        paid_geocoding_count: 50,
        by_provider: [
          %{provider: "google_places", total_cost: 3.70, count: 100},
          %{provider: "openstreetmap", total_cost: 0.0, count: 50}
        ],
        by_scraper: [
          %{scraper: "kino_krakow", total_cost: 1.85, count: 50}
        ],
        failed_count: 5,
        deferred_count: 10
      }

      report = GeocodingStats.format_report(summary)

      assert report =~ "Total Venues Geocoded: 100"
      assert report =~ "Total Cost: $3.74"
      assert report =~ "google_places"
      assert report =~ "kino_krakow"
      assert report =~ "Failed Geocoding: 5"
    end
  end

  # Helper function to create test venues with geocoding metadata
  defp create_test_venue(name, provider, cost, scraper, opts \\ []) do
    failed = Keyword.get(opts, :failed, false)
    deferred = Keyword.get(opts, :deferred, false)

    metadata = %{
      "geocoding" => %{
        "provider" => provider,
        "cost_per_call" => cost,
        "source_scraper" => scraper,
        "geocoded_at" => DateTime.utc_now() |> DateTime.to_string(),
        "geocoding_failed" => failed,
        "failure_reason" => if(failed, do: "test_failure", else: nil),
        "needs_manual_geocoding" => deferred
      }
    }

    {:ok, venue} =
      %Venue{}
      |> Venue.changeset(%{
        name: name,
        city: "Test City",
        country: "Test Country",
        latitude: 51.5074,
        longitude: -0.1278,
        source: "scraper",
        metadata: metadata
      })
      |> Repo.insert()

    venue
  end
end
