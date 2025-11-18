defmodule EventasaurusDiscovery.JobExecutionSummariesTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.JobExecutionSummaries
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  describe "record_execution/1" do
    test "records a successful job execution" do
      attrs = %{
        job_id: 123,
        worker: "TestWorker",
        queue: "default",
        state: "completed",
        results: %{items_processed: 10},
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 1500
      }

      assert {:ok, summary} = JobExecutionSummary.record_execution(attrs)
      assert summary.job_id == 123
      assert summary.worker == "TestWorker"
      assert summary.state == "completed"
      assert summary.results == %{items_processed: 10}
      assert summary.duration_ms == 1500
    end

    test "records a failed job execution with error" do
      attrs = %{
        job_id: 456,
        worker: "TestWorker",
        queue: "default",
        state: "discarded",
        error: "Something went wrong",
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 500
      }

      assert {:ok, summary} = JobExecutionSummary.record_execution(attrs)
      assert summary.state == "discarded"
      assert summary.error == "Something went wrong"
    end

    test "validates required fields" do
      attrs = %{
        results: %{items_processed: 10}
      }

      assert {:error, changeset} = JobExecutionSummary.record_execution(attrs)
      assert %{job_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates state must be valid" do
      attrs = %{
        job_id: 789,
        worker: "TestWorker",
        queue: "default",
        state: "invalid_state",
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }

      assert {:error, changeset} = JobExecutionSummary.record_execution(attrs)
      assert %{state: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_summaries/1" do
    setup do
      # Create some test summaries
      {:ok, summary1} =
        JobExecutionSummary.record_execution(%{
          job_id: 1,
          worker: "WorkerA",
          queue: "default",
          state: "completed",
          attempted_at: DateTime.add(DateTime.utc_now(), -3600, :second),
          completed_at: DateTime.add(DateTime.utc_now(), -3500, :second),
          duration_ms: 100_000
        })

      {:ok, summary2} =
        JobExecutionSummary.record_execution(%{
          job_id: 2,
          worker: "WorkerB",
          queue: "scraper",
          state: "discarded",
          attempted_at: DateTime.add(DateTime.utc_now(), -1800, :second),
          completed_at: DateTime.add(DateTime.utc_now(), -1700, :second),
          duration_ms: 100_000
        })

      {:ok, summary3} =
        JobExecutionSummary.record_execution(%{
          job_id: 3,
          worker: "WorkerA",
          queue: "default",
          state: "completed",
          attempted_at: DateTime.add(DateTime.utc_now(), -900, :second),
          completed_at: DateTime.add(DateTime.utc_now(), -800, :second),
          duration_ms: 100_000
        })

      {:ok, summary1: summary1, summary2: summary2, summary3: summary3}
    end

    test "returns all summaries by default" do
      summaries = JobExecutionSummaries.list_summaries()
      assert length(summaries) == 3
    end

    test "filters by worker" do
      summaries = JobExecutionSummaries.list_summaries(worker: "WorkerA")
      assert length(summaries) == 2
      assert Enum.all?(summaries, &(&1.worker == "WorkerA"))
    end

    test "filters by state" do
      summaries = JobExecutionSummaries.list_summaries(state: "discarded")
      assert length(summaries) == 1
      assert hd(summaries).state == "discarded"
    end

    test "respects limit option" do
      summaries = JobExecutionSummaries.list_summaries(limit: 1)
      assert length(summaries) == 1
    end

    test "orders by attempted_at descending by default" do
      summaries = JobExecutionSummaries.list_summaries()
      assert summaries |> hd() |> Map.get(:job_id) == 3
    end
  end

  describe "list_workers/0" do
    setup do
      # Create summaries for different workers
      JobExecutionSummary.record_execution(%{
        job_id: 1,
        worker: "WorkerA",
        queue: "default",
        state: "completed",
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      JobExecutionSummary.record_execution(%{
        job_id: 2,
        worker: "WorkerA",
        queue: "default",
        state: "completed",
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      JobExecutionSummary.record_execution(%{
        job_id: 3,
        worker: "WorkerB",
        queue: "scraper",
        state: "completed",
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

      :ok
    end

    test "returns unique workers with execution counts" do
      workers = JobExecutionSummaries.list_workers()
      assert length(workers) == 2

      worker_a = Enum.find(workers, &(&1.worker == "WorkerA"))
      assert worker_a.total_executions == 2

      worker_b = Enum.find(workers, &(&1.worker == "WorkerB"))
      assert worker_b.total_executions == 1
    end
  end

  describe "get_worker_metrics/1" do
    setup do
      # Create mixed success/failure summaries
      JobExecutionSummary.record_execution(%{
        job_id: 1,
        worker: "TestWorker",
        queue: "default",
        state: "completed",
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 1000
      })

      JobExecutionSummary.record_execution(%{
        job_id: 2,
        worker: "TestWorker",
        queue: "default",
        state: "completed",
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 2000
      })

      JobExecutionSummary.record_execution(%{
        job_id: 3,
        worker: "TestWorker",
        queue: "default",
        state: "discarded",
        attempted_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        duration_ms: 500
      })

      :ok
    end

    test "calculates metrics correctly" do
      metrics = JobExecutionSummaries.get_worker_metrics("TestWorker")

      assert metrics.total_jobs == 3
      assert metrics.completed == 2
      assert metrics.failed == 1
      assert metrics.success_rate == 66.67
      assert metrics.avg_duration_ms == 1166.67
    end
  end

  describe "delete_old_summaries/1" do
    setup do
      # Create old and new summaries
      old_date = DateTime.add(DateTime.utc_now(), -100, :day)
      recent_date = DateTime.add(DateTime.utc_now(), -10, :day)

      {:ok, _old} =
        JobExecutionSummary.record_execution(%{
          job_id: 1,
          worker: "OldWorker",
          queue: "default",
          state: "completed",
          attempted_at: old_date,
          completed_at: old_date
        })

      {:ok, _recent} =
        JobExecutionSummary.record_execution(%{
          job_id: 2,
          worker: "RecentWorker",
          queue: "default",
          state: "completed",
          attempted_at: recent_date,
          completed_at: recent_date
        })

      :ok
    end

    test "deletes summaries older than specified days" do
      {deleted_count, _} = JobExecutionSummaries.delete_old_summaries(90)
      assert deleted_count == 1

      summaries = JobExecutionSummaries.list_summaries()
      assert length(summaries) == 1
      assert hd(summaries).worker == "RecentWorker"
    end
  end
end
