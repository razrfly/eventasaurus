defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob do
  @moduledoc """
  Main orchestration job for Geeks Who Drink scraper.

  Responsibilities:
  - Fetch WordPress nonce from venues page
  - Enqueue index job with nonce and US map bounds
  - Supports limit parameter for testing

  ## Workflow
  1. Extract WordPress nonce (required for AJAX API)
  2. Enqueue IndexJob with nonce and map bounds
  3. IndexJob handles venue discovery and schedules detail jobs
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

    # Extract nonce for WordPress AJAX API authentication
    case GeeksWhoDrink.Extractors.NonceExtractor.fetch_nonce() do
      {:ok, nonce} ->
        Logger.info("✅ Successfully fetched WordPress nonce")

        # Enqueue index job with nonce and US bounds
        %{
          "source_id" => source.id,
          "nonce" => nonce,
          "bounds" => GeeksWhoDrink.Config.us_bounds(),
          "limit" => limit
        }
        |> GeeksWhoDrink.Jobs.IndexJob.new()
        |> Oban.insert()

        Logger.info("✅ Enqueued index job for Geeks Who Drink")
        {:ok, %{source_id: source.id, limit: limit}}

      {:error, reason} = error ->
        Logger.error("❌ Failed to fetch nonce: #{inspect(reason)}")
        error
    end
  end
end
