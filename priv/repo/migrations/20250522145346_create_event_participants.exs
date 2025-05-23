defmodule EventasaurusApp.Repo.Migrations.CreateEventParticipants do
  use Ecto.Migration

  def change do
    create table(:event_participants) do
      add :role, :string, null: false
      add :status, :string, null: false
      add :source, :string
      add :metadata, :map

      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:event_participants, [:event_id])
    create index(:event_participants, [:user_id])
    create unique_index(:event_participants, [:event_id, :user_id])
  end
end
