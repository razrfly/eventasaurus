defmodule EventasaurusDiscovery.Admin.DiscoveryStatsCollectorTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Admin.DiscoveryStatsCollector
  alias EventasaurusApp.Repo

  @moduletag :discovery_stats

  describe "get_source_stats/2 for city-specific sources" do
    test "returns correct data for source with completed jobs" do
      # Insert test Oban job
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
        args: %{"city_id" => 1, "limit" => 100},
        state: "completed",
        completed_at: ~U[2025-10-08 12:00:00.000000Z]
      })

      stats = DiscoveryStatsCollector.get_source_stats(1, "bandsintown")

      assert stats.run_count == 1
      assert stats.success_count == 1
      assert stats.error_count == 0
      assert stats.last_run_at == ~N[2025-10-08 12:00:00.000000]
      assert is_nil(stats.last_error)
    end

    test "returns zeros for source that never ran" do
      stats = DiscoveryStatsCollector.get_source_stats(1, "bandsintown")

      assert stats.run_count == 0
      assert stats.success_count == 0
      assert stats.error_count == 0
      assert is_nil(stats.last_run_at)
      assert is_nil(stats.last_error)
    end

    test "correctly counts success vs errors" do
      # Insert completed job
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed",
        completed_at: ~U[2025-10-08 12:00:00.000000Z]
      })

      # Insert discarded job with error
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "discarded",
        completed_at: ~U[2025-10-08 13:00:00.000000Z],
        errors: [%{"error" => "API rate limit exceeded"}]
      })

      stats = DiscoveryStatsCollector.get_source_stats(1, "ticketmaster")

      assert stats.run_count == 2
      assert stats.success_count == 1
      assert stats.error_count == 1
      assert stats.last_run_at == ~N[2025-10-08 13:00:00.000000]
      assert stats.last_error =~ "rate limit"
    end

    test "returns most recent error message" do
      # Insert multiple discarded jobs
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "discarded",
        completed_at: ~U[2025-10-08 12:00:00.000000Z],
        errors: [%{"error" => "Old error"}]
      })

      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "discarded",
        completed_at: ~U[2025-10-08 13:00:00.000000Z],
        errors: [%{"error" => "Recent error"}]
      })

      stats = DiscoveryStatsCollector.get_source_stats(1, "karnet")

      assert stats.error_count == 2
      assert stats.last_error == "Recent error"
    end

    test "filters by city_id correctly" do
      # Insert job for city 1
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed",
        completed_at: ~U[2025-10-08 12:00:00.000000Z]
      })

      # Insert job for city 2
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
        args: %{"city_id" => 2},
        state: "completed",
        completed_at: ~U[2025-10-08 13:00:00.000000Z]
      })

      # Query for city 1
      stats_city_1 = DiscoveryStatsCollector.get_source_stats(1, "bandsintown")
      assert stats_city_1.run_count == 1
      assert stats_city_1.last_run_at == ~N[2025-10-08 12:00:00.000000]

      # Query for city 2
      stats_city_2 = DiscoveryStatsCollector.get_source_stats(2, "bandsintown")
      assert stats_city_2.run_count == 1
      assert stats_city_2.last_run_at == ~N[2025-10-08 13:00:00.000000]
    end
  end

  describe "get_source_stats/2 for country-wide sources" do
    test "returns stats without city filter for country-wide sources" do
      # Insert jobs without city_id
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob",
        args: %{"limit" => 100},
        state: "completed",
        completed_at: ~U[2025-10-08 12:00:00.000000Z]
      })

      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob",
        args: %{"limit" => 100},
        state: "completed",
        completed_at: ~U[2025-10-08 13:00:00.000000Z]
      })

      stats = DiscoveryStatsCollector.get_source_stats(nil, "pubquiz-pl")

      assert stats.run_count == 2
      assert stats.success_count == 2
      assert stats.error_count == 0
      assert stats.last_run_at == ~N[2025-10-08 13:00:00.000000]
    end
  end

  describe "get_source_stats/2 input validation" do
    test "handles invalid city_id gracefully" do
      stats = DiscoveryStatsCollector.get_source_stats("invalid", "bandsintown")

      assert stats.run_count == 0
      assert stats.success_count == 0
      assert stats.error_count == 0
      assert is_nil(stats.last_run_at)
    end

    test "handles invalid source_name gracefully" do
      stats = DiscoveryStatsCollector.get_source_stats(1, 123)

      assert stats.run_count == 0
      assert is_nil(stats.last_run_at)
    end

    test "handles unknown source_name" do
      stats = DiscoveryStatsCollector.get_source_stats(1, "unknown-source")

      assert stats.run_count == 0
      assert is_nil(stats.last_run_at)
    end
  end

  describe "get_all_source_stats/2" do
    test "returns stats for all requested sources" do
      # Insert jobs for multiple sources
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed",
        completed_at: ~U[2025-10-08 12:00:00.000000Z]
      })

      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed",
        completed_at: ~U[2025-10-08 13:00:00.000000Z]
      })

      stats = DiscoveryStatsCollector.get_all_source_stats(1, ["bandsintown", "ticketmaster"])

      assert Map.has_key?(stats, "bandsintown")
      assert Map.has_key?(stats, "ticketmaster")
      assert stats["bandsintown"].run_count == 1
      assert stats["ticketmaster"].run_count == 1
    end

    test "handles mix of existing and non-existing sources" do
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed"
      })

      stats = DiscoveryStatsCollector.get_all_source_stats(1, ["bandsintown", "ticketmaster"])

      assert stats["bandsintown"].run_count == 1
      assert stats["ticketmaster"].run_count == 0
    end

    test "handles mix of city-specific and country-wide sources" do
      # City-specific source
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed",
        completed_at: ~U[2025-10-08 12:00:00.000000Z]
      })

      # Country-wide source
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Pubquiz.Jobs.SyncJob",
        args: %{"limit" => 100},
        state: "completed",
        completed_at: ~U[2025-10-08 13:00:00.000000Z]
      })

      stats = DiscoveryStatsCollector.get_all_source_stats(1, ["bandsintown", "pubquiz-pl"])

      assert stats["bandsintown"].run_count == 1
      assert stats["bandsintown"].last_run_at == ~N[2025-10-08 12:00:00.000000]
      assert stats["pubquiz-pl"].run_count == 1
      assert stats["pubquiz-pl"].last_run_at == ~N[2025-10-08 13:00:00.000000]
    end

    test "uses batched query for efficiency" do
      # This test verifies the function completes successfully with multiple sources
      # In a real scenario, you'd use query instrumentation to verify single query
      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed"
      })

      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed"
      })

      insert_oban_job(%{
        worker: "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
        args: %{"city_id" => 1},
        state: "completed"
      })

      stats =
        DiscoveryStatsCollector.get_all_source_stats(1, [
          "bandsintown",
          "ticketmaster",
          "karnet"
        ])

      assert Enum.all?(stats, fn {_source, data} -> data.run_count == 1 end)
    end

    test "handles invalid input gracefully" do
      stats = DiscoveryStatsCollector.get_all_source_stats("invalid", ["bandsintown"])

      assert stats == %{}
    end
  end

  # Helper function to insert Oban jobs for testing
  defp insert_oban_job(attrs) do
    defaults = %{
      state: "completed",
      queue: "discovery_import",
      worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
      args: %{},
      attempt: 1,
      max_attempts: 3,
      inserted_at: DateTime.utc_now(),
      scheduled_at: DateTime.utc_now(),
      attempted_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now()
    }

    attrs = Map.merge(defaults, attrs)

    %Oban.Job{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end
end
