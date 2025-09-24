defmodule EventasaurusApp.Repo.Migrations.CreateEventPlans do
  use Ecto.Migration

  def change do
    create table(:event_plans) do
      add :public_event_id, references(:public_events, on_delete: :delete_all), null: false
      add :private_event_id, references(:events, on_delete: :delete_all), null: false
      add :created_by, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    # Ensure a user can only have one plan per public event
    create unique_index(:event_plans, [:public_event_id, :private_event_id, :created_by])

    # Indexes for performance
    create index(:event_plans, [:public_event_id])
    create index(:event_plans, [:created_by])
    create index(:event_plans, [:private_event_id])
  end
end