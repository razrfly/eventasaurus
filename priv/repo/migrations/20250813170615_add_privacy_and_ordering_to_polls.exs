defmodule EventasaurusApp.Repo.Migrations.AddPrivacyAndOrderingToPolls do
  use Ecto.Migration

  def change do
    alter table(:polls) do
      # Privacy settings as JSON field for flexibility
      add :privacy_settings, :map, default: %{}
      
      # Order index for ordering multiple polls within an event
      add :order_index, :integer, default: 0
    end

    # Create index for efficient ordering queries
    create index(:polls, [:event_id, :order_index])
  end
end