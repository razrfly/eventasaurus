defmodule EventasaurusApp.Repo.Migrations.CreateEventActivities do
  use Ecto.Migration

  def change do
    create table(:event_activities) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :group_id, references(:groups, on_delete: :nilify_all)
      add :activity_type, :string, null: false
      add :metadata, :jsonb, null: false, default: fragment("'{}'::jsonb")
      add :occurred_at, :utc_datetime
      add :created_by_id, references(:users, on_delete: :nilify_all), null: true
      add :source, :string
      
      timestamps()
    end

    # Indexes for performance
    create index(:event_activities, [:event_id])
    create index(:event_activities, [:group_id, :activity_type])
    create index(:event_activities, [:group_id, :occurred_at])
  end
end
