defmodule EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary do
  @moduledoc """
  Schema for tracking Oban job execution summaries.

  This provides historical tracking of job executions beyond Oban's retention period,
  with flexible metadata for scraper-specific metrics.

  ## Phase 1: MVP
  Generic schema that works for ALL scrapers. Each scraper can store custom metrics
  in the `results` JSONB field:

  - DayPageJob: %{showtimes_scheduled: 25, movies_scheduled: 5}
  - MovieDetailJob: %{status: :matched, tmdb_id: 123, confidence: 0.85}
  - ShowtimeProcessJob: %{outcome: :created, event_id: 456}

  ## Usage

      # Record a job execution (typically called from telemetry handler)
      JobExecutionSummary.record_execution(%{
        job_id: 123,
        worker: "EventasaurusDiscovery.Sources.Repertuary.Jobs.DayPageJob",
        queue: :scraper_index,
        state: :completed,
        results: %{showtimes_scheduled: 25, movies_scheduled: 5},
        attempted_at: ~U[2024-01-15 10:00:00Z],
        completed_at: ~U[2024-01-15 10:01:30Z],
        duration_ms: 90000
      })
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "job_execution_summaries" do
    # Core Oban job reference
    field(:job_id, :integer)
    field(:worker, :string)
    field(:queue, :string)
    field(:state, :string)

    # Job data (snapshot at completion/failure time)
    field(:args, :map, default: %{})

    # Results - generic JSONB for scraper-specific metrics
    field(:results, :map, default: %{})

    # Error tracking
    field(:error, :string)

    # Timing
    field(:attempted_at, :utc_datetime)
    field(:completed_at, :utc_datetime)
    field(:duration_ms, :integer)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating job execution summaries.
  """
  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :job_id,
      :worker,
      :queue,
      :state,
      :args,
      :results,
      :error,
      :attempted_at,
      :completed_at,
      :duration_ms
    ])
    |> validate_required([:job_id, :worker, :queue, :state])
    |> validate_inclusion(:state, ["completed", "discarded", "cancelled", "retryable"])
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
  end

  @doc """
  Convenience function to record a job execution.
  Returns {:ok, summary} or {:error, changeset}.
  """
  def record_execution(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> EventasaurusApp.Repo.insert()
  end
end
