defmodule EventasaurusApp.Repo.Migrations.MakeSourceExternalIdUnique do
  use Ecto.Migration

  def change do
    # Drop the existing non-unique index
    drop_if_exists index(:public_event_sources, [:source_id, :external_id])

    # Create unique index to enforce per-source external_id uniqueness
    create unique_index(:public_event_sources, [:source_id, :external_id])
  end
end
