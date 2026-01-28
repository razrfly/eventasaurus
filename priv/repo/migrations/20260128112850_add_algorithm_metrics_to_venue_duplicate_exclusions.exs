defmodule EventasaurusApp.Repo.Migrations.AddAlgorithmMetricsToVenueDuplicateExclusions do
  use Ecto.Migration

  def change do
    alter table(:venue_duplicate_exclusions) do
      # Algorithm metrics at time of exclusion (for improving detection)
      add :confidence_score, :decimal, precision: 5, scale: 4
      add :distance_meters, :integer
      add :similarity_score, :decimal, precision: 5, scale: 4
      # Note: reason column already exists from original migration

      # For Phase 3: soft delete support
      add :removed_at, :utc_datetime
      add :removed_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:venue_duplicate_exclusions, [:removed_at])
  end
end
