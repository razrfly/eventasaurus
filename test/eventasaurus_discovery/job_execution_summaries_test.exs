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
      assert metrics.pipeline_health == 66.67
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

  describe "get_source_pipeline_metrics/2" do
    setup do
      now = DateTime.utc_now()

      # Create Cinema City pipeline jobs
      JobExecutionSummary.record_execution(%{
        job_id: 1,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 2100
      })

      JobExecutionSummary.record_execution(%{
        job_id: 2,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 8500
      })

      JobExecutionSummary.record_execution(%{
        job_id: 3,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
        queue: "discovery",
        state: "discarded",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500
      })

      JobExecutionSummary.record_execution(%{
        job_id: 4,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 1800
      })

      # Create Kino Krakow job (different source)
      JobExecutionSummary.record_execution(%{
        job_id: 5,
        worker: "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 1500
      })

      :ok
    end

    test "returns metrics grouped by job type for a specific source" do
      metrics = JobExecutionSummaries.get_source_pipeline_metrics("cinema_city", 24)

      assert length(metrics) == 3
      assert Enum.all?(metrics, &(&1.worker =~ "CinemaCity"))
    end

    test "sorts SyncJob first, then others alphabetically" do
      metrics = JobExecutionSummaries.get_source_pipeline_metrics("cinema_city", 24)

      assert hd(metrics).job_type == "SyncJob"
    end

    test "calculates pipeline health correctly per job type" do
      metrics = JobExecutionSummaries.get_source_pipeline_metrics("cinema_city", 24)

      cinema_date_metrics = Enum.find(metrics, &(&1.job_type == "CinemaDateJob"))
      assert cinema_date_metrics.total_runs == 2
      assert cinema_date_metrics.completed == 1
      assert cinema_date_metrics.failed == 1
      assert cinema_date_metrics.pipeline_health == 50.0
    end

    test "does not include jobs from other sources" do
      metrics = JobExecutionSummaries.get_source_pipeline_metrics("cinema_city", 24)

      refute Enum.any?(metrics, &(&1.worker =~ "KinoKrakow"))
    end

    test "includes retryable jobs in processing_failure_rate calculation" do
      now = DateTime.utc_now()

      # Create a source with retryable jobs
      JobExecutionSummary.record_execution(%{
        job_id: 100,
        worker: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 1000
      })

      JobExecutionSummary.record_execution(%{
        job_id: 101,
        worker: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob",
        queue: "discovery",
        state: "retryable",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500
      })

      JobExecutionSummary.record_execution(%{
        job_id: 102,
        worker: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob",
        queue: "discovery",
        state: "retryable",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500
      })

      metrics = JobExecutionSummaries.get_source_pipeline_metrics("repertuary", 24)
      sync_job_metrics = Enum.find(metrics, &(&1.job_type == "SyncJob"))

      assert sync_job_metrics.total_runs == 3
      assert sync_job_metrics.completed == 1
      assert sync_job_metrics.retryable == 2
      # Processing failure rate should include retryable jobs: 2/3 = 66.67%
      assert sync_job_metrics.processing_failure_rate == 66.67
      # Pipeline health should not count retryable as healthy: 1/3 = 33.33%
      assert sync_job_metrics.pipeline_health == 33.33
    end

    test "retryable jobs count separate from failed/discarded" do
      now = DateTime.utc_now()

      JobExecutionSummary.record_execution(%{
        job_id: 200,
        worker: "EventasaurusDiscovery.Sources.TestSource.Jobs.SyncJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 1000
      })

      JobExecutionSummary.record_execution(%{
        job_id: 201,
        worker: "EventasaurusDiscovery.Sources.TestSource.Jobs.SyncJob",
        queue: "discovery",
        state: "discarded",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500
      })

      JobExecutionSummary.record_execution(%{
        job_id: 202,
        worker: "EventasaurusDiscovery.Sources.TestSource.Jobs.SyncJob",
        queue: "discovery",
        state: "retryable",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500
      })

      metrics = JobExecutionSummaries.get_source_pipeline_metrics("test_source", 24)
      sync_job_metrics = Enum.find(metrics, &(&1.job_type == "SyncJob"))

      assert sync_job_metrics.completed == 1
      assert sync_job_metrics.failed == 1
      assert sync_job_metrics.retryable == 1
      assert sync_job_metrics.total_runs == 3
      # Processing failure rate: (0 cancelled_failed + 1 discarded + 1 retryable) / 3 = 66.67%
      assert sync_job_metrics.processing_failure_rate == 66.67
    end
  end

  describe "get_source_error_breakdown/2" do
    setup do
      now = DateTime.utc_now()

      # Create failed jobs with error categories
      JobExecutionSummary.record_execution(%{
        job_id: 1,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
        queue: "discovery",
        state: "discarded",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500,
        results: %{
          error_category: "network_error",
          error_message: "Request timeout after 30000ms"
        }
      })

      JobExecutionSummary.record_execution(%{
        job_id: 2,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
        queue: "discovery",
        state: "discarded",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500,
        results: %{
          error_category: "network_error",
          error_message: "Connection refused"
        }
      })

      JobExecutionSummary.record_execution(%{
        job_id: 3,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
        queue: "discovery",
        state: "discarded",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500,
        results: %{
          error_category: "validation_error",
          error_message: "Missing required field: title"
        }
      })

      # Different source
      JobExecutionSummary.record_execution(%{
        job_id: 4,
        worker: "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob",
        queue: "discovery",
        state: "discarded",
        attempted_at: now,
        completed_at: now,
        duration_ms: 500,
        results: %{
          error_category: "network_error",
          error_message: "API failure"
        }
      })

      :ok
    end

    test "returns error breakdown by job type and category" do
      errors = JobExecutionSummaries.get_source_error_breakdown("cinema_city", 24)

      assert length(errors) == 2
      assert Enum.all?(errors, &(&1.worker =~ "CinemaCity"))
    end

    test "groups errors by job type and category" do
      errors = JobExecutionSummaries.get_source_error_breakdown("cinema_city", 24)

      cinema_date_network =
        Enum.find(
          errors,
          &(&1.job_type == "CinemaDateJob" && &1.error_category == "network_error")
        )

      assert cinema_date_network.count == 2
      assert cinema_date_network.example_error =~ ~r/(timeout|refused)/

      movie_detail_validation =
        Enum.find(
          errors,
          &(&1.job_type == "MovieDetailJob" && &1.error_category == "validation_error")
        )

      assert movie_detail_validation.count == 1
    end

    test "does not include errors from other sources" do
      errors = JobExecutionSummaries.get_source_error_breakdown("cinema_city", 24)

      refute Enum.any?(errors, &(&1.worker =~ "KinoKrakow"))
    end
  end

  describe "get_source_recent_pipeline_runs/2" do
    setup do
      now = DateTime.utc_now()

      # Create a successful pipeline run
      JobExecutionSummary.record_execution(%{
        job_id: 1,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 2100
      })

      JobExecutionSummary.record_execution(%{
        job_id: 2,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
        queue: "discovery",
        state: "completed",
        attempted_at: DateTime.add(now, 2, :second),
        completed_at: DateTime.add(now, 2, :second),
        duration_ms: 8500
      })

      JobExecutionSummary.record_execution(%{
        job_id: 3,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
        queue: "discovery",
        state: "completed",
        attempted_at: DateTime.add(now, 4, :second),
        completed_at: DateTime.add(now, 4, :second),
        duration_ms: 1800
      })

      # Create a failed pipeline run (1 hour ago)
      one_hour_ago = DateTime.add(now, -3600, :second)

      JobExecutionSummary.record_execution(%{
        job_id: 4,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
        queue: "discovery",
        state: "completed",
        attempted_at: one_hour_ago,
        completed_at: one_hour_ago,
        duration_ms: 2100
      })

      JobExecutionSummary.record_execution(%{
        job_id: 5,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
        queue: "discovery",
        state: "discarded",
        attempted_at: DateTime.add(one_hour_ago, 2, :second),
        completed_at: DateTime.add(one_hour_ago, 2, :second),
        duration_ms: 500,
        results: %{
          error_category: "network_error",
          error_message: "Request timeout"
        }
      })

      :ok
    end

    test "returns recent pipeline runs grouped by SyncJob execution" do
      runs = JobExecutionSummaries.get_source_recent_pipeline_runs("cinema_city", 20)

      assert length(runs) == 2
    end

    test "groups jobs within 5 minute time window" do
      runs = JobExecutionSummaries.get_source_recent_pipeline_runs("cinema_city", 20)

      successful_run = Enum.find(runs, &(&1.status == :success))
      assert successful_run.total_jobs == 3
      assert length(successful_run.stages) == 3
    end

    test "calculates pipeline statistics correctly" do
      runs = JobExecutionSummaries.get_source_recent_pipeline_runs("cinema_city", 20)

      successful_run = Enum.find(runs, &(&1.status == :success))
      assert successful_run.completed_jobs == 3
      assert successful_run.failed_jobs == 0
      assert successful_run.total_duration_ms == 12400
    end

    test "identifies failed stage in failed pipeline" do
      runs = JobExecutionSummaries.get_source_recent_pipeline_runs("cinema_city", 20)

      failed_run = Enum.find(runs, &(&1.status == :failed))
      assert failed_run.failed_stage == "CinemaDateJob"
      assert failed_run.failed_jobs == 1
    end

    test "includes error details in stages" do
      runs = JobExecutionSummaries.get_source_recent_pipeline_runs("cinema_city", 20)

      failed_run = Enum.find(runs, &(&1.status == :failed))
      failed_stage = Enum.find(failed_run.stages, &(&1.state == "discarded"))
      assert failed_stage.error_category == "network_error"
      assert failed_stage.error_message == "Request timeout"
    end
  end

  describe "get_scraper_metrics/1 with job_type_count" do
    setup do
      now = DateTime.utc_now()

      # Cinema City with 3 different job types
      JobExecutionSummary.record_execution(%{
        job_id: 1,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 2100
      })

      JobExecutionSummary.record_execution(%{
        job_id: 2,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.CinemaDateJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 8500
      })

      JobExecutionSummary.record_execution(%{
        job_id: 3,
        worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.MovieDetailJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 1800
      })

      # Kino Krakow with 1 job type
      JobExecutionSummary.record_execution(%{
        job_id: 4,
        worker: "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob",
        queue: "discovery",
        state: "completed",
        attempted_at: now,
        completed_at: now,
        duration_ms: 1500
      })

      :ok
    end

    test "includes job_type_count in scraper metrics" do
      metrics = JobExecutionSummaries.get_scraper_metrics(24)

      cinema_city = Enum.find(metrics, &(&1.scraper_name == "cinema_city"))
      assert cinema_city.job_type_count == 3

      kino_krakow = Enum.find(metrics, &(&1.scraper_name == "kino_krakow"))
      assert kino_krakow.job_type_count == 1
    end

    test "includes last_run timestamp" do
      metrics = JobExecutionSummaries.get_scraper_metrics(24)

      cinema_city = Enum.find(metrics, &(&1.scraper_name == "cinema_city"))
      assert %DateTime{} = cinema_city.last_run
    end
  end
end
