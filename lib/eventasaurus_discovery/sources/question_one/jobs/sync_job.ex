defmodule EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob do
  @moduledoc """
  Main orchestration job for Question One scraper.

  Responsibilities:
  - Enqueue the first index page job
  - Index job handles pagination and schedules detail jobs
  - Supports limit parameter for testing
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3,
    priority: 1

  require Logger
  alias EventasaurusDiscovery.Sources.{SourceStore, QuestionOne}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("🔄 Starting Question One sync job")

    limit = args["limit"]
    source = SourceStore.get_by_key!(QuestionOne.Source.key())

    # Enqueue first index page job (starts at page 1)
    %{
      "source_id" => source.id,
      "page" => 1,
      "limit" => limit
    }
    |> QuestionOne.Jobs.IndexPageJob.new()
    |> Oban.insert()

    Logger.info("✅ Enqueued index page job 1 for Question One")
    {:ok, %{source_id: source.id, limit: limit}}
  end
end
