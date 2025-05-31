defmodule Eventasaurus.Repo.Migrations.CreateEventDateOptions do
  use Ecto.Migration

  def change do
    create table(:event_date_options) do
      add :event_date_poll_id, references(:event_date_polls, on_delete: :delete_all), null: false
      add :date, :date, null: false

      timestamps()
    end

    create index(:event_date_options, [:event_date_poll_id])

    # Ensure no duplicate dates per poll
    create unique_index(:event_date_options, [:event_date_poll_id, :date])

    # Index for finding options by date for queries
    create index(:event_date_options, [:date])
  end
end
