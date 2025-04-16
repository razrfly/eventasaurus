defmodule EventasaurusApp.Repo.Migrations.CreateEventUsers do
  use Ecto.Migration

  def change do
    create table(:event_users) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string

      timestamps()
    end

    create index(:event_users, [:event_id])
    create index(:event_users, [:user_id])
    create unique_index(:event_users, [:event_id, :user_id])
  end
end
