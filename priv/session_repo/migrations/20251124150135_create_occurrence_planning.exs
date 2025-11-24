defmodule EventasaurusApp.SessionRepo.Migrations.CreateOccurrencePlanning do
  use Ecto.Migration

  def change do
    create table(:occurrence_planning) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :poll_id, references(:polls, on_delete: :delete_all), null: false

      # Polymorphic reference to "series" entity (movie, venue, activity, etc.)
      add :series_type, :string
      add :series_id, :bigint

      # The result - NULL until poll finalizes, then links to created event_plan
      add :event_plan_id, references(:event_plans, on_delete: :nilify_all)

      # Optional: filters used to generate options
      add :filter_criteria, :jsonb, default: "{}"

      timestamps()
    end

    create index(:occurrence_planning, [:event_id])
    create index(:occurrence_planning, [:poll_id])
    create unique_index(:occurrence_planning, [:event_id, :poll_id])
    create index(:occurrence_planning, [:series_type, :series_id])
  end
end
