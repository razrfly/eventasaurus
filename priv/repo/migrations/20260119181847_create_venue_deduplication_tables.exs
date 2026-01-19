defmodule EventasaurusApp.Repo.Migrations.CreateVenueDeduplicationTables do
  use Ecto.Migration

  def change do
    # Audit trail for venue merges - enables rollback and tracking
    create table(:venue_merge_audit) do
      add :source_venue_id, :bigint, null: false
      add :target_venue_id, references(:venues, on_delete: :nilify_all), null: false
      add :merged_by_user_id, references(:users, on_delete: :nilify_all)
      add :merge_reason, :string
      add :similarity_score, :float
      add :distance_meters, :float
      add :events_reassigned, :integer, default: 0
      add :public_events_reassigned, :integer, default: 0
      add :source_venue_snapshot, :map, null: false

      timestamps()
    end

    create index(:venue_merge_audit, [:target_venue_id])
    create index(:venue_merge_audit, [:merged_by_user_id])
    create index(:venue_merge_audit, [:inserted_at])

    # Exclusions - pairs explicitly marked as "not duplicates"
    create table(:venue_duplicate_exclusions) do
      add :venue_id_1, references(:venues, on_delete: :delete_all), null: false
      add :venue_id_2, references(:venues, on_delete: :delete_all), null: false
      add :excluded_by_user_id, references(:users, on_delete: :nilify_all)
      add :reason, :string

      timestamps()
    end

    # Ensure venue_id_1 < venue_id_2 for consistent storage (normalized pair)
    # This prevents storing both (A, B) and (B, A)
    create unique_index(:venue_duplicate_exclusions, [:venue_id_1, :venue_id_2],
      name: :venue_duplicate_exclusions_pair_index
    )

    create index(:venue_duplicate_exclusions, [:venue_id_1])
    create index(:venue_duplicate_exclusions, [:venue_id_2])
  end
end
