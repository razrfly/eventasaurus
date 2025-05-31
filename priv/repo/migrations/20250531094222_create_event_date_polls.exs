defmodule Eventasaurus.Repo.Migrations.CreateEventDatePolls do
  use Ecto.Migration

  def change do
    create table(:event_date_polls) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all), null: false
      add :voting_deadline, :utc_datetime
      add :finalized_date, :date

      timestamps()
    end

    create index(:event_date_polls, [:created_by_id])

    # Ensure one poll per event
    create unique_index(:event_date_polls, [:event_id])

    # Index for finding polls by deadline for cleanup/notification jobs
    create index(:event_date_polls, [:voting_deadline])
  end
end
