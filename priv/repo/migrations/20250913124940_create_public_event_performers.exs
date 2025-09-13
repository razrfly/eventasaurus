defmodule EventasaurusApp.Repo.Migrations.CreatePublicEventPerformers do
  use Ecto.Migration

  def change do
    create table(:public_event_performers) do
      add :event_id, references(:public_events, on_delete: :delete_all), null: false
      add :performer_id, references(:performers, on_delete: :restrict), null: false
      add :billing_order, :integer, default: 0
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:public_event_performers, [:event_id, :performer_id])
    create index(:public_event_performers, [:performer_id])
  end
end