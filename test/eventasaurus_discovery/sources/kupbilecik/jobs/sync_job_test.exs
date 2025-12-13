defmodule EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJobTest do
  use Eventasaurus.DataCase, async: true
  use Oban.Testing, repo: EventasaurusApp.Repo

  alias EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJob

  describe "perform/1" do
    test "successfully syncs events" do
      args = %{
        "from_date" => "2024-01-01",
        "to_date" => "2024-01-31"
      }

      # TODO: Mock external API calls
      # Execute job
      assert {:ok, _result} = perform_job(SyncJob, args)
    end

    test "records success with MetricsTracker" do
      args = %{"from_date" => "2024-01-01"}

      perform_job(SyncJob, args)

      # TODO: Verify MetricsTracker.record_success was called
      # Check job_execution_summaries table
    end

    test "records failure with MetricsTracker on error" do
      # TODO: Mock API to return error
      # Verify MetricsTracker.record_failure was called
    end
  end
end
