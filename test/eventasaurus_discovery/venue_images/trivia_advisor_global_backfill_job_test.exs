defmodule EventasaurusDiscovery.VenueImages.TriviaAdvisorGlobalBackfillJobTest do
  use EventasaurusApp.DataCase, async: true
  use Oban.Testing, repo: EventasaurusApp.Repo

  import EventasaurusApp.Factory

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

  describe "perform/1 execution paths" do
    setup do
      # Set up environment variable for tests that need it
      original_value = System.get_env("TRIVIA_ADVISOR_DATABASE_URL")
      System.put_env("TRIVIA_ADVISOR_DATABASE_URL", "postgres://test:test@localhost/test")

      on_exit(fn ->
        if original_value do
          System.put_env("TRIVIA_ADVISOR_DATABASE_URL", original_value)
        else
          System.delete_env("TRIVIA_ADVISOR_DATABASE_URL")
        end
      end)

      :ok
    end

    test "dry run completes successfully without spawning city jobs" do
      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue(dry_run: true)

      oban_job = %Oban.Job{
        id: job.id,
        args: job.args,
        worker: job.worker,
        queue: job.queue,
        meta: %{}
      }

      # Dry run should complete successfully
      assert :ok = TriviaAdvisorGlobalBackfillJob.perform(oban_job)
    end

    test "dry run with force parameter completes successfully" do
      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue(dry_run: true, force: true)

      oban_job = %Oban.Job{
        id: job.id,
        args: job.args,
        worker: job.worker,
        queue: job.queue,
        meta: %{}
      }

      assert :ok = TriviaAdvisorGlobalBackfillJob.perform(oban_job)
    end

    test "handles empty city list gracefully" do
      # With no cities having venue coordinates, should still complete
      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue(dry_run: true)

      oban_job = %Oban.Job{
        id: job.id,
        args: job.args,
        worker: job.worker,
        queue: job.queue,
        meta: %{}
      }

      # Should succeed even with no cities
      assert :ok = TriviaAdvisorGlobalBackfillJob.perform(oban_job)
    end

    test "actual execution spawns city jobs when cities exist" do
      # Create a city with a venue that has coordinates
      city = insert(:city, name: "Test City", slug: "test-city")

      insert(:venue,
        slug: "test-venue-1",
        city_id: city.id,
        city_ref: city,
        latitude: 52.2297,
        longitude: 21.0122
      )

      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

      oban_job = %Oban.Job{
        id: job.id,
        args: job.args,
        worker: job.worker,
        queue: job.queue,
        meta: %{}
      }

      # Should complete and spawn city jobs
      assert :ok = TriviaAdvisorGlobalBackfillJob.perform(oban_job)

      # Verify city-level job was enqueued
      assert_enqueued(
        worker: EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob,
        args: %{"city_id" => city.id, "limit" => -1, "force" => false}
      )
    end

    test "force mode passes force flag to city jobs" do
      city = insert(:city, name: "Force Test City", slug: "force-test-city")

      insert(:venue,
        slug: "force-venue-1",
        city_id: city.id,
        city_ref: city,
        latitude: 52.2297,
        longitude: 21.0122
      )

      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue(force: true)

      oban_job = %Oban.Job{
        id: job.id,
        args: job.args,
        worker: job.worker,
        queue: job.queue,
        meta: %{}
      }

      assert :ok = TriviaAdvisorGlobalBackfillJob.perform(oban_job)

      # Verify force flag is passed to city job
      assert_enqueued(
        worker: EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob,
        args: %{"city_id" => city.id, "limit" => -1, "force" => true}
      )
    end

    test "processes multiple cities independently" do
      city1 = insert(:city, name: "City One", slug: "city-one")
      city2 = insert(:city, name: "City Two", slug: "city-two")

      insert(:venue,
        slug: "venue-city-one",
        city_id: city1.id,
        city_ref: city1,
        latitude: 52.2297,
        longitude: 21.0122
      )

      insert(:venue,
        slug: "venue-city-two",
        city_id: city2.id,
        city_ref: city2,
        latitude: 50.0647,
        longitude: 19.9450
      )

      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

      oban_job = %Oban.Job{
        id: job.id,
        args: job.args,
        worker: job.worker,
        queue: job.queue,
        meta: %{}
      }

      assert :ok = TriviaAdvisorGlobalBackfillJob.perform(oban_job)

      # Verify both city jobs were enqueued
      assert_enqueued(
        worker: EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob,
        args: %{"city_id" => city1.id, "limit" => -1, "force" => false}
      )

      assert_enqueued(
        worker: EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob,
        args: %{"city_id" => city2.id, "limit" => -1, "force" => false}
      )
    end

    test "only spawns jobs for cities with venues that have coordinates" do
      # City with venues that have coordinates gets a job
      city_with_venues = insert(:city, name: "With Venues", slug: "with-venues")

      insert(:venue,
        slug: "venue-with-coords",
        city_id: city_with_venues.id,
        city_ref: city_with_venues,
        latitude: 52.2297,
        longitude: 21.0122
      )

      # City without any venues gets no job
      _city_without_venues = insert(:city, name: "Without Venues", slug: "without-venues")

      {:ok, job} = TriviaAdvisorGlobalBackfillJob.enqueue()

      oban_job = %Oban.Job{
        id: job.id,
        args: job.args,
        worker: job.worker,
        queue: job.queue,
        meta: %{}
      }

      assert :ok = TriviaAdvisorGlobalBackfillJob.perform(oban_job)

      # Only city with venues should have job enqueued
      assert_enqueued(
        worker: EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob,
        args: %{"city_id" => city_with_venues.id, "limit" => -1, "force" => false}
      )
    end
  end
end
