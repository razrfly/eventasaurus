defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob do
  @moduledoc """
  Main orchestration job for Geeks Who Drink scraper.

  Responsibilities:
  - Enqueue index job with US map bounds
  - Supports limit parameter for testing

  ## Workflow
  1. Enqueue IndexJob with map bounds
  2. IndexJob fetches fresh nonce (WordPress nonces expire in 12-24 hours)
  3. IndexJob handles venue discovery and schedules detail jobs

  Note: IndexJob fetches its own fresh nonce to avoid stale nonce issues
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3,
    priority: 1

  require Logger
  alias EventasaurusDiscovery.Sources.{SourceStore, GeeksWhoDrink}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🔄 Starting Geeks Who Drink sync job")

    limit = args["limit"]
    source = SourceStore.get_by_key!(GeeksWhoDrink.Source.key())

    # Enqueue index job with US bounds
    # Note: IndexJob fetches its own fresh nonce to avoid expiration issues
    %{
      "source_id" => source.id,
      "bounds" => GeeksWhoDrink.Config.us_bounds(),
      "limit" => limit
    }
    |> GeeksWhoDrink.Jobs.IndexJob.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.info("✅ Enqueued index job for Geeks Who Drink")
        {:ok, %{source_id: source.id, limit: limit}}

      {:error, reason} = error ->
        Logger.error("❌ Failed to enqueue index job: #{inspect(reason)}")
        error
    end
  end
end
