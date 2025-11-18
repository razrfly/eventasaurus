defmodule EventasaurusApp.Repo.Migrations.CreateJobExecutionSummaries do
  use Ecto.Migration

  def change do
    create table(:job_execution_summaries) do
      # Core Oban job reference
      add :job_id, :bigint, null: false
      add :worker, :string, null: false
      add :queue, :string, null: false
      add :state, :string, null: false

      # Job data (snapshot at completion/failure time)
      add :args, :map, default: %{}

      # Results - generic JSONB for scraper-specific metrics
      # Each scraper can store whatever makes sense:
      # - events_created, movies_scheduled, showtimes_processed, etc.
      add :results, :map, default: %{}

      # Error tracking
      add :error, :text

      # Timing
      add :attempted_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :duration_ms, :integer

      timestamps(type: :utc_datetime)
    end

    # Indexes for common queries
    create index(:job_execution_summaries, [:job_id])
    create index(:job_execution_summaries, [:worker])
    create index(:job_execution_summaries, [:state])
    create index(:job_execution_summaries, [:worker, :attempted_at])
    create index(:job_execution_summaries, [:attempted_at])
  end
end
