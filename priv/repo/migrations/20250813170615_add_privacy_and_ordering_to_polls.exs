defmodule EventasaurusApp.Repo.Migrations.AddPrivacyAndOrderingToPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      # Privacy settings as JSON field for flexibility
      add :privacy_settings, :map, default: %{}, null: false
      
      # Order index for ordering multiple polls within an event
      add :order_index, :integer, default: 0, null: false
    end

    # Create partial index for efficient ordering queries (only non-deleted polls)
    # This improves performance by excluding soft-deleted records from the index
    create index(:polls, [:event_id, :order_index], 
      where: "deleted_at IS NULL",
      name: :polls_event_id_order_index_active)
  end
end