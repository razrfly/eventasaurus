defmodule EventasaurusApp.Repo.Migrations.AddEventSourcesFreshnessIndex do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:public_event_sources, [:source_id, :external_id, :last_seen_at],
      name: :idx_event_sources_freshness,
      concurrently: true
    )
  end

  def down do
    drop_if_exists index(:public_event_sources, [:source_id, :external_id, :last_seen_at],
      name: :idx_event_sources_freshness
    )
  end
end
