defmodule EventasaurusDiscovery.Monitoring.CollisionsTest do
  @moduledoc """
  Tests for the Collisions monitoring module.

  Tests collision listing, statistics, overlap matrix, and confidence distribution
  functionality for deduplication monitoring.
  """
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusDiscovery.Monitoring.Collisions
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusApp.Repo

  # Helper to create job execution summaries with collision data
  defp create_job_summary(attrs) do
    defaults = %{
      job_id: System.unique_integer([:positive]),
      worker: "EventasaurusDiscovery.Sources.Kupbilecik.Jobs.EventDetailJob",
      queue: "scraper_detail",
      state: "completed",
      args: %{},
      results: %{},
      attempted_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now(),
      duration_ms: 100
    }

    merged = Map.merge(defaults, attrs)

    %JobExecutionSummary{}
    |> JobExecutionSummary.changeset(merged)
    |> Repo.insert!()
  end

  defp create_collision_job(source, type, opts \\ []) do
    worker = "EventasaurusDiscovery.Sources.#{Macro.camelize(source)}.Jobs.EventDetailJob"

    collision_data =
      %{
        "type" => type,
        "matched_event_id" => opts[:matched_event_id] || 123,
        "resolution" => opts[:resolution] || "deferred"
      }
      |> maybe_add_cross_source_fields(type, opts)

    results =
      %{
        "collision_data" => collision_data,
        "external_id" => opts[:external_id] || "#{source}_event_#{:rand.uniform(10000)}"
      }
      |> Map.merge(opts[:extra_results] || %{})

    job =
      create_job_summary(%{
        worker: worker,
        results: results
      })

    # If inserted_at is specified, update it directly (bypasses timestamps)
    if opts[:inserted_at] do
      import Ecto.Query

      from(j in JobExecutionSummary, where: j.id == ^job.id)
      |> Repo.update_all(set: [inserted_at: opts[:inserted_at]])
    end

    job
  end

  defp maybe_add_cross_source_fields(collision_data, "cross_source", opts) do
    collision_data
    |> Map.put("matched_source", opts[:matched_source] || "bandsintown")
    |> Map.put("confidence", opts[:confidence] || 0.85)
    |> Map.put("match_factors", opts[:match_factors] || ["performer", "venue", "date"])
  end

  defp maybe_add_cross_source_fields(collision_data, _type, _opts), do: collision_data

  defp create_non_collision_job(source) do
    worker = "EventasaurusDiscovery.Sources.#{Macro.camelize(source)}.Jobs.EventDetailJob"

    create_job_summary(%{
      worker: worker,
      results: %{
        "status" => "success",
        "external_id" => "#{source}_event_#{:rand.uniform(10000)}"
      }
    })
  end

  describe "list/1" do
    test "returns empty list when no collisions exist" do
      create_non_collision_job("kupbilecik")

      assert {:ok, []} = Collisions.list()
    end

    test "returns collision records" do
      create_collision_job("kupbilecik", "same_source")

      assert {:ok, [collision]} = Collisions.list()
      assert collision.source == "kupbilecik"
      assert collision.type == "same_source"
    end

    test "limits results" do
      for _ <- 1..5, do: create_collision_job("kupbilecik", "same_source")

      assert {:ok, collisions} = Collisions.list(limit: 3)
      assert length(collisions) == 3
    end

    test "filters by source" do
      create_collision_job("kupbilecik", "same_source")
      create_collision_job("bandsintown", "same_source")

      assert {:ok, collisions} = Collisions.list(source: "kupbilecik")
      assert length(collisions) == 1
      assert hd(collisions).source == "kupbilecik"
    end

    test "filters by collision type" do
      create_collision_job("kupbilecik", "same_source")
      create_collision_job("kupbilecik", "cross_source")

      assert {:ok, collisions} = Collisions.list(type: "cross_source")
      assert length(collisions) == 1
      assert hd(collisions).type == "cross_source"
    end

    test "includes cross-source collision details" do
      create_collision_job("kupbilecik", "cross_source",
        matched_source: "bandsintown",
        confidence: 0.92,
        match_factors: ["performer", "venue", "date", "gps"]
      )

      assert {:ok, [collision]} = Collisions.list()
      assert collision.type == "cross_source"
      assert collision.matched_source == "bandsintown"
      assert collision.confidence == 0.92
      assert collision.match_factors == ["performer", "venue", "date", "gps"]
    end

    test "filters by time range" do
      # Old collision (2 days ago)
      old_time = NaiveDateTime.add(NaiveDateTime.utc_now(), -48 * 3600, :second)
      create_collision_job("kupbilecik", "same_source", inserted_at: old_time)

      # Recent collision
      create_collision_job("kupbilecik", "same_source")

      assert {:ok, collisions} = Collisions.list(hours: 24)
      assert length(collisions) == 1
    end
  end

  describe "stats/1" do
    test "returns zero stats when no jobs exist" do
      assert {:ok, stats} = Collisions.stats()

      assert stats.total_processed == 0
      assert stats.total_collisions == 0
      assert stats.same_source_count == 0
      assert stats.cross_source_count == 0
      assert stats.collision_rate == 0.0
    end

    test "calculates collision statistics" do
      # Create non-collision jobs
      for _ <- 1..8, do: create_non_collision_job("kupbilecik")

      # Create collision jobs
      create_collision_job("kupbilecik", "same_source")
      create_collision_job("kupbilecik", "cross_source", confidence: 0.80)

      assert {:ok, stats} = Collisions.stats()

      assert stats.total_processed == 10
      assert stats.total_collisions == 2
      assert stats.same_source_count == 1
      assert stats.cross_source_count == 1
      assert stats.collision_rate == 20.0
    end

    test "calculates average confidence for cross-source collisions" do
      create_collision_job("kupbilecik", "cross_source", confidence: 0.80)
      create_collision_job("kupbilecik", "cross_source", confidence: 0.90)

      assert {:ok, stats} = Collisions.stats()

      # Average of 0.80 and 0.90 = 0.85
      assert stats.avg_confidence == 0.85
    end

    test "groups statistics by source" do
      # Kupbilecik: 3 processed, 1 collision
      create_non_collision_job("kupbilecik")
      create_non_collision_job("kupbilecik")
      create_collision_job("kupbilecik", "same_source")

      # Bandsintown: 2 processed, 1 collision
      create_non_collision_job("bandsintown")
      create_collision_job("bandsintown", "cross_source")

      assert {:ok, stats} = Collisions.stats()

      # Both sources should be in by_source
      sources = Enum.map(stats.by_source, & &1.source)
      assert "kupbilecik" in sources
      assert "bandsintown" in sources

      # Check kupbilecik stats
      kup_stats = Enum.find(stats.by_source, &(&1.source == "kupbilecik"))
      assert kup_stats.processed == 3
      assert kup_stats.same_source == 1
      assert kup_stats.cross_source == 0
    end

    test "filters by source" do
      create_collision_job("kupbilecik", "same_source")
      create_collision_job("bandsintown", "same_source")

      assert {:ok, stats} = Collisions.stats(source: "kupbilecik")

      assert stats.total_processed == 1
      assert stats.total_collisions == 1
    end
  end

  describe "overlap_matrix/1" do
    test "returns empty matrix when no cross-source collisions" do
      create_collision_job("kupbilecik", "same_source")

      assert {:ok, matrix} = Collisions.overlap_matrix()

      assert matrix.sources == []
      assert matrix.overlaps == []
    end

    test "builds overlap matrix from cross-source collisions" do
      create_collision_job("kupbilecik", "cross_source",
        matched_source: "bandsintown",
        confidence: 0.85
      )

      create_collision_job("kupbilecik", "cross_source",
        matched_source: "bandsintown",
        confidence: 0.90
      )

      create_collision_job("kupbilecik", "cross_source",
        matched_source: "week_pl",
        confidence: 0.75
      )

      assert {:ok, matrix} = Collisions.overlap_matrix()

      # Should have all involved sources
      assert "kupbilecik" in matrix.sources
      assert "bandsintown" in matrix.sources
      assert "week_pl" in matrix.sources

      # Should have overlap entries
      assert length(matrix.overlaps) == 2

      # kupbilecik->bandsintown should have 2 overlaps
      kup_bit = Enum.find(matrix.overlaps, &(&1.matched_source == "bandsintown"))
      assert kup_bit.count == 2
      # (0.85 + 0.90) / 2
      assert kup_bit.avg_confidence == 0.88

      # kupbilecik->week_pl should have 1 overlap
      kup_week = Enum.find(matrix.overlaps, &(&1.matched_source == "week_pl"))
      assert kup_week.count == 1
      assert kup_week.avg_confidence == 0.75
    end

    test "sorts overlaps by count descending" do
      # Create more overlaps for bandsintown
      for _ <- 1..3 do
        create_collision_job("kupbilecik", "cross_source", matched_source: "bandsintown")
      end

      # Fewer for week_pl
      create_collision_job("kupbilecik", "cross_source", matched_source: "week_pl")

      assert {:ok, matrix} = Collisions.overlap_matrix()

      # First should be bandsintown (3 overlaps)
      first = hd(matrix.overlaps)
      assert first.matched_source == "bandsintown"
      assert first.count == 3
    end
  end

  describe "confidence_distribution/1" do
    test "returns empty distribution when no cross-source collisions" do
      create_collision_job("kupbilecik", "same_source")

      assert {:ok, dist} = Collisions.confidence_distribution()

      assert dist.count == 0
      assert dist.min == nil
      assert dist.max == nil
      assert dist.histogram == []
    end

    test "calculates confidence distribution statistics" do
      # Create collisions with varying confidence
      create_collision_job("kupbilecik", "cross_source", confidence: 0.70)
      create_collision_job("kupbilecik", "cross_source", confidence: 0.80)
      create_collision_job("kupbilecik", "cross_source", confidence: 0.85)
      create_collision_job("kupbilecik", "cross_source", confidence: 0.90)

      assert {:ok, dist} = Collisions.confidence_distribution()

      assert dist.count == 4
      assert dist.min == 0.70
      assert dist.max == 0.90
      # (0.70 + 0.80 + 0.85 + 0.90) / 4 = 0.8125, rounded to 0.81
      assert dist.avg == 0.81
    end

    test "builds histogram buckets" do
      # Create collisions spread across confidence ranges
      create_collision_job("kupbilecik", "cross_source", confidence: 0.65)
      create_collision_job("kupbilecik", "cross_source", confidence: 0.75)
      create_collision_job("kupbilecik", "cross_source", confidence: 0.85)
      create_collision_job("kupbilecik", "cross_source", confidence: 0.95)

      assert {:ok, dist} = Collisions.confidence_distribution()

      # Should have non-empty histogram
      assert length(dist.histogram) > 0

      # Each bucket should have a count
      Enum.each(dist.histogram, fn bucket ->
        assert bucket.count > 0
        assert is_binary(bucket.range)
      end)
    end

    test "filters by source" do
      create_collision_job("kupbilecik", "cross_source", confidence: 0.80)
      create_collision_job("bandsintown", "cross_source", confidence: 0.90)

      assert {:ok, dist} = Collisions.confidence_distribution(source: "kupbilecik")

      assert dist.count == 1
      assert dist.avg == 0.80
    end
  end

  describe "summary/1" do
    test "returns summary metrics" do
      # Create some jobs
      for _ <- 1..5, do: create_non_collision_job("kupbilecik")
      create_collision_job("kupbilecik", "same_source")
      create_collision_job("kupbilecik", "cross_source", matched_source: "bandsintown")

      assert {:ok, summary} = Collisions.summary()

      assert summary.total_processed == 7
      assert summary.total_collisions == 2
      assert summary.same_source_count == 1
      assert summary.cross_source_count == 1
      assert summary.collision_rate > 0
    end

    test "includes top overlaps" do
      create_collision_job("kupbilecik", "cross_source", matched_source: "bandsintown")

      assert {:ok, summary} = Collisions.summary()

      assert length(summary.top_overlaps) > 0
    end
  end
end
