defmodule EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJobTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob

  describe "enqueue/1" do
    test "enqueues job with required city_id parameter" do
      assert {:ok, job} = TriviaAdvisorBackfillJob.enqueue(city_id: 1, limit: 5)

      assert job.worker == "EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob"
      assert job.queue == "venue_backfill"
      assert job.args["city_id"] == 1
      assert job.args["limit"] == 5
    end

    test "raises ArgumentError when city_id is missing" do
      assert_raise ArgumentError, "city_id is required", fn ->
        TriviaAdvisorBackfillJob.enqueue(limit: 5)
      end
    end

    test "applies development limit when in dev environment" do
      # In test environment, which is also considered dev
      assert {:ok, job} = TriviaAdvisorBackfillJob.enqueue(city_id: 1, limit: 100)

      # Should be capped at dev_limit (10)
      assert job.args["limit"] == 10
    end

    test "accepts dry_run parameter" do
      assert {:ok, job} = TriviaAdvisorBackfillJob.enqueue(city_id: 1, limit: 5, dry_run: true)

      assert job.args["dry_run"] == true
    end

    test "uses default limit when not specified" do
      assert {:ok, job} = TriviaAdvisorBackfillJob.enqueue(city_id: 1)

      # Should use dev_limit default (10)
      assert job.args["limit"] == 10
    end
  end

  describe "job metadata" do
    test "sets correct worker name" do
      {:ok, job} = TriviaAdvisorBackfillJob.enqueue(city_id: 1, limit: 5)

      assert job.worker == "EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob"
    end

    test "sets correct queue" do
      {:ok, job} = TriviaAdvisorBackfillJob.enqueue(city_id: 1, limit: 5)

      assert job.queue == "venue_backfill"
    end

    test "converts keyword args to string keys" do
      {:ok, job} = TriviaAdvisorBackfillJob.enqueue(city_id: 1, limit: 5, dry_run: true)

      # Verify all keys are strings
      assert is_binary(hd(Map.keys(job.args)))
    end
  end
end
