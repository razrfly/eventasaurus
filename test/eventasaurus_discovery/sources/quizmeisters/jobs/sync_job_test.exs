defmodule EventasaurusDiscovery.Sources.Quizmeisters.Jobs.SyncJobTest do
  use EventasaurusApp.DataCase, async: false
  use Oban.Testing, repo: EventasaurusApp.Repo

  alias EventasaurusDiscovery.Sources.Quizmeisters.Jobs.{SyncJob, IndexPageJob}
  alias EventasaurusDiscovery.Sources.SourceStore

  @moduletag :external_api

  describe "perform/1" do
    setup do
      # Create Quizmeisters source in test DB
      {:ok, source} =
        SourceStore.create_source(%{
          name: "Quizmeisters",
          key: "quizmeisters",
          enabled: true
        })

      %{source: source}
    end

    test "successfully fetches locations and enqueues index job", %{source: source} do
      # Perform sync job
      assert {:ok, result} =
               perform_job(SyncJob, %{
                 "limit" => 5
               })

      assert result.source_id == source.id
      assert result.locations_count > 0
      assert result.limit == 5

      # Verify IndexPageJob was enqueued
      assert_enqueued(worker: IndexPageJob, args: %{"source_id" => source.id, "limit" => 5})
    end

    test "handles missing source gracefully" do
      # Delete the source
      SourceStore.delete_source("quizmeisters")

      # Should fail with proper error
      assert {:error, _reason} =
               perform_job(SyncJob, %{
                 "limit" => 5
               })
    end
  end
end
