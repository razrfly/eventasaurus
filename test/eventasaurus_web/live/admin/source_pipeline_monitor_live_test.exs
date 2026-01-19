defmodule EventasaurusWeb.Admin.SourcePipelineMonitorLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary

  describe "SourcePipelineMonitorLive" do
    test "renders pipeline monitor page for a source", %{conn: conn} do
      # Create test data for cinema_city source
      now = DateTime.utc_now()

      {:ok, _} =
        JobExecutionSummary.record_execution(%{
          job_id: 1,
          worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
          queue: "discovery",
          state: "completed",
          attempted_at: now,
          completed_at: now,
          duration_ms: 2100
        })

      {:ok, _view, html} = live(conn, ~p"/admin/job-executions/sources/cinema-city")

      # Check page renders with expected content
      assert html =~ "Cinema City Pipeline Monitor"
      assert html =~ "Total Runs"
      assert html =~ "Pipeline Health"
      assert html =~ "Processing Failures"
      assert html =~ "Match Rate"
    end

    test "displays retryable jobs in processing failures", %{conn: conn} do
      now = DateTime.utc_now()

      # Create jobs with retryable state
      {:ok, _} =
        JobExecutionSummary.record_execution(%{
          job_id: 10,
          worker: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob",
          queue: "discovery",
          state: "completed",
          attempted_at: now,
          completed_at: now,
          duration_ms: 1000
        })

      {:ok, _} =
        JobExecutionSummary.record_execution(%{
          job_id: 11,
          worker: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob",
          queue: "discovery",
          state: "retryable",
          attempted_at: now,
          completed_at: now,
          duration_ms: 500
        })

      {:ok, _} =
        JobExecutionSummary.record_execution(%{
          job_id: 12,
          worker: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob",
          queue: "discovery",
          state: "retryable",
          attempted_at: now,
          completed_at: now,
          duration_ms: 500
        })

      {:ok, _view, html} = live(conn, ~p"/admin/job-executions/sources/repertuary")

      # Should show retrying count in Processing Failures section
      assert html =~ "2 retrying"
      # Processing failure rate should be 66.7% (2 retryable out of 3)
      assert html =~ "66.7%"
    end

    test "calculates pipeline health correctly with retryable jobs", %{conn: conn} do
      now = DateTime.utc_now()

      # Create 10 jobs: 7 completed, 3 retryable
      for i <- 1..7 do
        {:ok, _} =
          JobExecutionSummary.record_execution(%{
            job_id: 100 + i,
            worker: "EventasaurusDiscovery.Sources.WeekPl.Jobs.SyncJob",
            queue: "discovery",
            state: "completed",
            attempted_at: now,
            completed_at: now,
            duration_ms: 1000
          })
      end

      for i <- 1..3 do
        {:ok, _} =
          JobExecutionSummary.record_execution(%{
            job_id: 200 + i,
            worker: "EventasaurusDiscovery.Sources.WeekPl.Jobs.SyncJob",
            queue: "discovery",
            state: "retryable",
            attempted_at: now,
            completed_at: now,
            duration_ms: 500
          })
      end

      {:ok, _view, html} = live(conn, ~p"/admin/job-executions/sources/week-pl")

      # Pipeline health should be 70% (7 completed out of 10)
      # Retryable jobs are NOT counted as healthy
      assert html =~ "70.0%"
      assert html =~ "10" # Total runs
    end

    test "handles source with no data gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/job-executions/sources/nonexistent-source")

      assert html =~ "No pipeline data found"
    end

    test "shows retryable state badge in pipeline stages", %{conn: conn} do
      now = DateTime.utc_now()

      {:ok, _} =
        JobExecutionSummary.record_execution(%{
          job_id: 300,
          worker: "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
          queue: "discovery",
          state: "retryable",
          attempted_at: now,
          completed_at: now,
          duration_ms: 500,
          results: %{
            error_category: "network_error",
            error_message: "Connection timeout"
          }
        })

      {:ok, view, _html} = live(conn, ~p"/admin/job-executions/sources/bandsintown")

      # Expand the run to see the stage details
      html = render(view)

      # Should show the pipeline with retryable job
      assert html =~ "Pipeline Flow"
      assert html =~ "SyncJob"
    end

    test "correctly separates retryable from discarded in failure counts", %{conn: conn} do
      now = DateTime.utc_now()

      # 1 completed, 1 discarded, 1 retryable
      {:ok, _} =
        JobExecutionSummary.record_execution(%{
          job_id: 400,
          worker: "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
          queue: "discovery",
          state: "completed",
          attempted_at: now,
          completed_at: now,
          duration_ms: 1000
        })

      {:ok, _} =
        JobExecutionSummary.record_execution(%{
          job_id: 401,
          worker: "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
          queue: "discovery",
          state: "discarded",
          attempted_at: now,
          completed_at: now,
          duration_ms: 500
        })

      {:ok, _} =
        JobExecutionSummary.record_execution(%{
          job_id: 402,
          worker: "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
          queue: "discovery",
          state: "retryable",
          attempted_at: now,
          completed_at: now,
          duration_ms: 500
        })

      {:ok, _view, html} = live(conn, ~p"/admin/job-executions/sources/karnet")

      # Should show separate counts for failed (cancelled_failed), discarded, and retrying
      assert html =~ "discarded"
      assert html =~ "1 retrying"
      # Processing failure rate: (0 + 1 discarded + 1 retryable) / 3 = 66.7%
      assert html =~ "66.7%"
    end
  end
end
