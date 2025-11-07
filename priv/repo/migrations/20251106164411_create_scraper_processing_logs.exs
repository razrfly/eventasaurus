defmodule EventasaurusApp.Repo.Migrations.CreateScraperProcessingLogs do
  use Ecto.Migration

  def change do
    create table(:scraper_processing_logs) do
      # Source tracking
      add :source_id, references(:sources, on_delete: :nothing), null: false
      add :source_name, :text, null: false

      # Oban job link for debugging
      add :job_id, references(:oban_jobs, on_delete: :nothing)

      # Outcome
      add :status, :text, null: false

      # Error tracking (flexible - TEXT, not ENUMs!)
      add :error_type, :text
      add :error_message, :text

      # Flexible metadata - store ANYTHING here!
      add :metadata, :jsonb, default: "{}"

      # Timestamps
      add :processed_at, :utc_datetime, null: false, default: fragment("NOW()")

      timestamps(type: :utc_datetime)
    end

    # Add check constraint for status
    create constraint(:scraper_processing_logs, :valid_status,
             check: "status IN ('success', 'failure')"
           )

    # Essential indexes
    create index(:scraper_processing_logs, [:source_name, :status])
    create index(:scraper_processing_logs, [:error_type], where: "status = 'failure'")
    create index(:scraper_processing_logs, [:job_id])
    create index(:scraper_processing_logs, [:processed_at])
    create index(:scraper_processing_logs, [:metadata], using: :gin)
  end
end
