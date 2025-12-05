defmodule EventasaurusDiscovery.VenueImages.TriviaAdvisorGlobalBackfillJobTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.VenueImages.TriviaAdvisorGlobalBackfillJob

  describe "enqueue/1" do
    test "enqueues job with default parameters" do
      assert {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

      assert job.worker == "EventasaurusDiscovery.VenueImages.TriviaAdvisorGlobalBackfillJob"
      assert job.queue == "venue_backfill"
      assert job.args["dry_run"] == nil || job.args["dry_run"] == false
      assert job.args["force"] == nil || job.args["force"] == false
    end

    test "enqueues job with dry_run parameter" do
      assert {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue(dry_run: true)

      assert job.args["dry_run"] == true
    end

    test "enqueues job with force parameter" do
      assert {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue(force: true)

      assert job.args["force"] == true
    end

    test "enqueues job with both dry_run and force parameters" do
      assert {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue(dry_run: true, force: true)

      assert job.args["dry_run"] == true
      assert job.args["force"] == true
    end
  end

  describe "job metadata" do
    test "sets correct worker name" do
      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

      assert job.worker == "EventasaurusDiscovery.VenueImages.TriviaAdvisorGlobalBackfillJob"
    end

    test "sets correct queue" do
      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

      assert job.queue == "venue_backfill"
    end

    test "sets max_attempts to 1" do
      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

      assert job.max_attempts == 1
    end

    test "sets priority to 1 (high priority)" do
      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

      assert job.priority == 1
    end

    test "converts keyword args to string keys" do
      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue(dry_run: true, force: true)

      # Verify all keys are strings
      assert Map.has_key?(job.args, "dry_run")
      assert Map.has_key?(job.args, "force")
      refute Map.has_key?(job.args, :dry_run)
      refute Map.has_key?(job.args, :force)
    end
  end

  describe "perform/1 validation" do
    test "fails when TRIVIA_ADVISOR_DATABASE_URL is not set" do
      # Ensure the env var is not set for this test
      original_value = System.get_env("TRIVIA_ADVISOR_DATABASE_URL")
      System.delete_env("TRIVIA_ADVISOR_DATABASE_URL")

      try do
        {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

        # Create a mock Oban.Job struct
        oban_job = %Oban.Job{
          id: job.id,
          args: job.args,
          worker: job.worker,
          queue: job.queue,
          meta: %{}
        }

        # Perform should fail with missing env var error
        result = TriviaAdvisorGlobalBackfillJob.perform(oban_job)
        assert {:error, "TRIVIA_ADVISOR_DATABASE_URL not set in environment"} = result
      after
        # Restore original value if it existed
        if original_value do
          System.put_env("TRIVIA_ADVISOR_DATABASE_URL", original_value)
        end
      end
    end
  end
end
