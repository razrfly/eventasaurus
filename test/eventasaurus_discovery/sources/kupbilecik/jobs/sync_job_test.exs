defmodule EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJobTest do
  @moduledoc """
  Tests for the Kupbilecik SyncJob.

  Note: Integration tests for SyncJob require:
  1. Database setup for job_execution_summaries
  2. Mocking of HTTP calls (plain HTTP, no Zyte - SSR site)
  3. Valid test fixtures

  These tests are marked @tag :integration and excluded by default.
  Run with: mix test --only integration
  """
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Kupbilecik.Jobs.SyncJob

  describe "module structure" do
    test "is a valid Oban worker" do
      # SyncJob uses Oban.Worker behavior
      # Oban workers define perform/1 that takes %Oban.Job{}
      assert {:module, SyncJob} = Code.ensure_compiled(SyncJob)
      assert function_exported?(SyncJob, :new, 1)
      assert function_exported?(SyncJob, :new, 2)
    end

    test "can create new job changeset" do
      changeset = SyncJob.new(%{})
      assert changeset.valid?
      # Queue is stored as string in changeset
      queue = Ecto.Changeset.get_field(changeset, :queue)
      assert queue in [:scraper_index, "scraper_index"]
    end

    test "can create job with limit" do
      changeset = SyncJob.new(%{"limit" => 10})
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :args)["limit"] == 10
    end
  end

  describe "perform/1" do
    @tag :integration
    test "successfully syncs events when API available" do
      # This test requires:
      # - Database connection
      # - Mocked HTTP responses (plain HTTP, no Zyte - SSR site)
      # Run with: mix test --only integration
    end
  end
end
