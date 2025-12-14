defmodule EventasaurusDiscovery.Metrics.MetricsTrackerCollisionTest do
  @moduledoc """
  Tests for collision/deduplication metrics tracking in MetricsTracker.

  Tests the collision_data recording functionality including:
  - Same-source collision tracking (external_id match)
  - Cross-source collision tracking (fuzzy match)
  - Collision data retrieval helpers
  - Integration with record_success/3
  """
  use EventasaurusApp.DataCase, async: false
  use Oban.Testing, repo: EventasaurusApp.Repo

  alias EventasaurusDiscovery.Metrics.MetricsTracker

  # Insert a real Oban job into the database for tests
  # Uses raw SQL to insert a valid Oban job since Oban.Testing doesn't
  # expose a direct way to create jobs with specific attributes
  defp insert_oban_job(opts \\ []) do
    worker = opts[:worker] || "TestWorker"
    args = opts[:args] || %{}
    meta = opts[:meta] || %{}
    queue = opts[:queue] || "default"

    now = DateTime.utc_now()

    {:ok, job} =
      Repo.insert(%Oban.Job{
        worker: worker,
        queue: queue,
        args: args,
        meta: meta,
        state: "executing",
        inserted_at: now,
        scheduled_at: now
      })

    job
  end

  describe "record_collision/3" do
    test "records same-source collision with required fields" do
      job = insert_oban_job()
      external_id = "test_event_123"

      collision_data = %{
        type: :same_source,
        matched_event_id: 456,
        resolution: "deferred"
      }

      assert {:ok, updated_job} =
               MetricsTracker.record_collision(job, external_id, collision_data)

      assert updated_job.meta["status"] == "success"
      assert updated_job.meta["external_id"] == external_id
      assert updated_job.meta["collision_data"]["type"] == "same_source"
      assert updated_job.meta["collision_data"]["matched_event_id"] == 456
      assert updated_job.meta["collision_data"]["confidence"] == 1.0
      assert updated_job.meta["collision_data"]["resolution"] == "deferred"
    end

    test "records cross-source collision with all fields" do
      job = insert_oban_job()
      external_id = "kupbilecik_event_789"

      collision_data = %{
        type: :cross_source,
        matched_event_id: 123,
        matched_source: "bandsintown",
        confidence: 0.85,
        match_factors: ["performer", "venue", "date", "gps"],
        resolution: "deferred"
      }

      assert {:ok, updated_job} =
               MetricsTracker.record_collision(job, external_id, collision_data)

      assert updated_job.meta["collision_data"]["type"] == "cross_source"
      assert updated_job.meta["collision_data"]["matched_event_id"] == 123
      assert updated_job.meta["collision_data"]["matched_source"] == "bandsintown"
      assert updated_job.meta["collision_data"]["confidence"] == 0.85

      assert updated_job.meta["collision_data"]["match_factors"] == [
               "performer",
               "venue",
               "date",
               "gps"
             ]

      assert updated_job.meta["collision_data"]["resolution"] == "deferred"
    end

    test "returns error when missing required fields" do
      job = insert_oban_job()

      # Missing type
      collision_data = %{matched_event_id: 123}

      assert {:error, :missing_required_fields} =
               MetricsTracker.record_collision(job, "ext_1", collision_data)

      # Missing matched_event_id
      collision_data = %{type: :same_source}

      assert {:error, :missing_required_fields} =
               MetricsTracker.record_collision(job, "ext_2", collision_data)
    end

    test "normalizes collision type from atom to string" do
      job = insert_oban_job()

      collision_data = %{
        type: :cross_source,
        matched_event_id: 100
      }

      assert {:ok, updated_job} = MetricsTracker.record_collision(job, "ext_id", collision_data)
      assert updated_job.meta["collision_data"]["type"] == "cross_source"
    end

    test "normalizes collision type from string to string" do
      job = insert_oban_job()

      collision_data = %{
        "type" => "same_source",
        "matched_event_id" => 100
      }

      assert {:ok, updated_job} = MetricsTracker.record_collision(job, "ext_id", collision_data)
      assert updated_job.meta["collision_data"]["type"] == "same_source"
    end

    test "sets default confidence of 1.0 for same_source collisions" do
      job = insert_oban_job()

      collision_data = %{
        type: :same_source,
        matched_event_id: 100
      }

      assert {:ok, updated_job} = MetricsTracker.record_collision(job, "ext_id", collision_data)
      assert updated_job.meta["collision_data"]["confidence"] == 1.0
    end

    test "does not set default confidence for cross_source collisions" do
      job = insert_oban_job()

      collision_data = %{
        type: :cross_source,
        matched_event_id: 100
      }

      assert {:ok, updated_job} = MetricsTracker.record_collision(job, "ext_id", collision_data)
      # confidence should be nil or not present since no default for cross_source
      refute Map.has_key?(updated_job.meta["collision_data"], "confidence")
    end

    test "includes processed_at timestamp" do
      job = insert_oban_job()

      collision_data = %{
        type: :same_source,
        matched_event_id: 100
      }

      assert {:ok, updated_job} = MetricsTracker.record_collision(job, "ext_id", collision_data)
      assert updated_job.meta["processed_at"]
      # Verify it's a valid ISO8601 timestamp
      assert {:ok, _, _} = DateTime.from_iso8601(updated_job.meta["processed_at"])
    end
  end

  describe "record_success/3 with collision_data" do
    test "records success with collision context when event created despite match" do
      job = insert_oban_job()
      external_id = "kupbilecik_event_555"

      opts = %{
        collision_data: %{
          type: :cross_source,
          matched_event_id: 999,
          matched_source: "week_pl",
          confidence: 0.75,
          match_factors: ["performer", "date"],
          resolution: "created"
        }
      }

      assert {:ok, updated_job} = MetricsTracker.record_success(job, external_id, opts)

      assert updated_job.meta["status"] == "success"
      assert updated_job.meta["collision_data"]["type"] == "cross_source"
      assert updated_job.meta["collision_data"]["matched_source"] == "week_pl"
      assert updated_job.meta["collision_data"]["resolution"] == "created"
    end

    test "records success without collision_data when no match found" do
      job = insert_oban_job()
      external_id = "kupbilecik_event_777"

      assert {:ok, updated_job} = MetricsTracker.record_success(job, external_id)

      assert updated_job.meta["status"] == "success"
      refute Map.has_key?(updated_job.meta, "collision_data")
    end
  end

  describe "collision data helpers" do
    test "get_collision_data/1 returns collision data when present" do
      job = insert_oban_job()

      collision_data = %{
        type: :same_source,
        matched_event_id: 100
      }

      {:ok, updated_job} = MetricsTracker.record_collision(job, "ext_id", collision_data)

      result = MetricsTracker.get_collision_data(updated_job)
      assert result["type"] == "same_source"
      assert result["matched_event_id"] == 100
    end

    test "get_collision_data/1 returns nil when no collision data" do
      job = insert_oban_job()
      {:ok, updated_job} = MetricsTracker.record_success(job, "ext_id")

      assert is_nil(MetricsTracker.get_collision_data(updated_job))
    end

    test "has_collision?/1 returns true when collision data present" do
      job = insert_oban_job()

      {:ok, updated_job} =
        MetricsTracker.record_collision(job, "ext_id", %{type: :same_source, matched_event_id: 1})

      assert MetricsTracker.has_collision?(updated_job)
    end

    test "has_collision?/1 returns false when no collision data" do
      job = insert_oban_job()
      {:ok, updated_job} = MetricsTracker.record_success(job, "ext_id")

      refute MetricsTracker.has_collision?(updated_job)
    end

    test "get_collision_type/1 returns collision type" do
      job = insert_oban_job()

      {:ok, updated_job} =
        MetricsTracker.record_collision(job, "ext_id", %{type: :cross_source, matched_event_id: 1})

      assert MetricsTracker.get_collision_type(updated_job) == "cross_source"
    end

    test "get_collision_type/1 returns nil when no collision" do
      job = insert_oban_job()
      {:ok, updated_job} = MetricsTracker.record_success(job, "ext_id")

      assert is_nil(MetricsTracker.get_collision_type(updated_job))
    end
  end

  describe "collision data persisted to database" do
    test "collision data is persisted in Oban job meta" do
      job = insert_oban_job()

      collision_data = %{
        type: :cross_source,
        matched_event_id: 456,
        matched_source: "bandsintown",
        confidence: 0.92,
        match_factors: ["performer", "venue", "date"],
        resolution: "deferred"
      }

      {:ok, _updated_job} = MetricsTracker.record_collision(job, "ext_id", collision_data)

      # Reload from database to verify persistence
      reloaded_job = Repo.get!(Oban.Job, job.id)

      assert reloaded_job.meta["status"] == "success"
      assert reloaded_job.meta["collision_data"]["type"] == "cross_source"
      assert reloaded_job.meta["collision_data"]["matched_event_id"] == 456
      assert reloaded_job.meta["collision_data"]["matched_source"] == "bandsintown"
      assert reloaded_job.meta["collision_data"]["confidence"] == 0.92

      assert reloaded_job.meta["collision_data"]["match_factors"] == [
               "performer",
               "venue",
               "date"
             ]

      assert reloaded_job.meta["collision_data"]["resolution"] == "deferred"
    end
  end
end
