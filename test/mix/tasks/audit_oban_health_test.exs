defmodule Mix.Tasks.Audit.ObanHealthTest do
  @moduledoc """
  Integration tests for the audit.oban_health mix task functionality.

  Tests focus on the job retry/cancel functionality and Oban integration.
  """
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusApp.ObanRepo

  import Ecto.Query

  # Test the underlying Oban operations that the mix task uses
  describe "job retry functionality" do
    setup do
      # Insert a test job directly using correct Oban.Job.new/2 API
      {:ok, job} =
        Oban.Job.new(%{test: true}, worker: "TestWorker", queue: "default")
        |> ObanRepo.insert()

      # Transition job to discarded state (can be retried)
      ObanRepo.update_all(
        from(j in "oban_jobs", where: j.id == ^job.id),
        set: [state: "discarded", discarded_at: DateTime.utc_now()]
      )

      {:ok, job: job}
    end

    test "Oban.retry_job/1 queues discarded job for retry", %{job: job} do
      # Verify job is in discarded state
      query = from(j in "oban_jobs", where: j.id == ^job.id, select: j.state)
      assert ObanRepo.one(query) == "discarded"

      # Retry the job
      result = Oban.retry_job(job.id)
      assert result in [:ok, {:ok, 1}]

      # Verify job is now available
      assert ObanRepo.one(query) == "available"
    end

    test "Oban.retry_job/1 returns error for non-existent job" do
      # This should either error or return a result indicating no rows affected
      result = Oban.retry_job(999_999_999)
      # Oban may return :ok with 0 affected or an error tuple
      assert result in [:ok, {:ok, 0}, {:error, :not_found}]
    end
  end

  describe "job cancel functionality" do
    setup do
      # Insert a test job in available state
      {:ok, job} =
        Oban.Job.new(%{test: true}, worker: "TestWorker", queue: "default")
        |> ObanRepo.insert()

      {:ok, job: job}
    end

    test "Oban.cancel_job/1 cancels available job", %{job: job} do
      # Verify job is in available state
      query = from(j in "oban_jobs", where: j.id == ^job.id, select: j.state)
      assert ObanRepo.one(query) == "available"

      # Cancel the job
      result = Oban.cancel_job(job.id)
      assert result in [:ok, {:ok, 1}]

      # Verify job is now cancelled
      assert ObanRepo.one(query) == "cancelled"
    end
  end

  describe "job querying for display" do
    setup do
      # Insert a test job with various attributes
      {:ok, job} =
        Oban.Job.new(
          %{cinema_id: "123", date: "2024-01-01"},
          worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
          queue: "discovery",
          max_attempts: 3
        )
        |> ObanRepo.insert()

      {:ok, job: job}
    end

    test "can query job details from oban_jobs table", %{job: job} do
      query =
        from(j in "oban_jobs",
          where: j.id == ^job.id,
          select: %{
            id: j.id,
            queue: j.queue,
            worker: j.worker,
            state: j.state,
            attempt: j.attempt,
            max_attempts: j.max_attempts,
            scheduled_at: j.scheduled_at,
            attempted_at: j.attempted_at
          }
        )

      result = ObanRepo.one(query)

      assert result.id == job.id
      assert result.queue == "discovery"
      assert result.worker == "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob"
      assert result.state == "available"
      assert result.max_attempts == 3
    end

    test "can query job with errors field", %{job: job} do
      # Add an error to the job
      ObanRepo.update_all(
        from(j in "oban_jobs", where: j.id == ^job.id),
        set: [
          state: "retryable",
          attempt: 1,
          errors: [%{"attempt" => 1, "at" => DateTime.utc_now() |> DateTime.to_iso8601(), "error" => "Test error"}]
        ]
      )

      query =
        from(j in "oban_jobs",
          where: j.id == ^job.id,
          select: %{
            id: j.id,
            state: j.state,
            attempt: j.attempt,
            errors: j.errors
          }
        )

      result = ObanRepo.one(query)

      assert result.state == "retryable"
      assert result.attempt == 1
      assert length(result.errors) == 1
      assert hd(result.errors)["error"] == "Test error"
    end

    test "returns nil for non-existent job" do
      query =
        from(j in "oban_jobs",
          where: j.id == 999_999_999,
          select: %{id: j.id}
        )

      assert ObanRepo.one(query) == nil
    end
  end

  describe "ObanJobSanitizerWorker integration" do
    alias EventasaurusApp.Workers.ObanJobSanitizerWorker

    test "detect_all/0 returns detection results" do
      result = ObanJobSanitizerWorker.detect_all()

      assert is_map(result)
      assert Map.has_key?(result, :zombie_available)
      assert Map.has_key?(result, :priority_zero_blockers)
      assert Map.has_key?(result, :stuck_executing)

      assert is_list(result.zombie_available)
      assert is_list(result.priority_zero_blockers)
      assert is_list(result.stuck_executing)
    end

    test "sanitizer worker can be enqueued" do
      assert {:ok, job} = ObanJobSanitizerWorker.new(%{}) |> Oban.insert()
      assert job.id != nil
      assert job.worker == "EventasaurusApp.Workers.ObanJobSanitizerWorker"
    end
  end
end
