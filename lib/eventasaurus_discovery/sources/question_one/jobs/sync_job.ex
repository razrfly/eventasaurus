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
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    external_id = "question_one_sync_#{Date.utc_today()}"
    Logger.info("🔄 Starting Question One sync job")

    limit = args["limit"]
    force = args["force"] || false

    source = SourceStore.get_by_key!(QuestionOne.Source.key())

    if is_nil(source) do
      MetricsTracker.record_failure(job, "Source not found: question_one", external_id)
      {:error, :source_not_found}
    else
        if force do
          Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
        end

        # Enqueue first index page job (starts at page 1)
        args = %{
          "source_id" => source.id,
          "page" => 1,
          "limit" => limit,
          "force" => force
        }

        case QuestionOne.Jobs.IndexPageJob.new(args) |> Oban.insert() do
          {:ok, _index_job} ->
            Logger.info("✅ Enqueued index page job 1 for Question One")
            MetricsTracker.record_success(job, external_id)
            {:ok, %{source_id: source.id, limit: limit, force: force}}

          {:error, reason} = error ->
            Logger.error("❌ Failed to enqueue Question One index page job: #{inspect(reason)}")
            MetricsTracker.record_failure(
              job,
              "Enqueue failed: #{inspect(reason)}",
              external_id
            )
            error
        end
    end
  end
end
