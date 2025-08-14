defmodule EventasaurusApp.Repo.Migrations.AddPrivacyAndOrderingToPolls do
  use Ecto.Migration

  # Enable concurrent index creation to avoid long locks on large tables
  @disable_ddl_transaction true

  def change do
    alter table(:polls) do
      # Privacy settings as JSON field for flexibility
      add :privacy_settings, :map, default: %{}, null: false
      
      # Order index for ordering multiple polls within an event
      add :order_index, :integer, default: 0, null: false
    end

    # Defensive drop to avoid duplicate indexes if one exists already
    drop_if_exists index(:polls, [:event_id, :order_index])

    # Create partial index for efficient ordering queries (only non-deleted polls)
    # This improves performance by excluding soft-deleted records from the index
    # Use concurrently to reduce locking on large tables
    create index(:polls, [:event_id, :order_index], 
      where: "deleted_at IS NULL",
      name: :polls_event_id_order_index_active,
      concurrently: true)
  end
end