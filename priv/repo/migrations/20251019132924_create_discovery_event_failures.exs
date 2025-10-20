defmodule EventasaurusApp.Repo.Migrations.CreateDiscoveryEventFailures do
  use Ecto.Migration

  def change do
    create table(:discovery_event_failures) do
      add :source_id, references(:sources, on_delete: :delete_all), null: false
      add :error_category, :string, null: false
      add :error_message, :text, null: false
      add :sample_external_ids, {:array, :string}, default: []
      add :occurrence_count, :integer, default: 1, null: false
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false

      timestamps()
    end

    # Index for querying failures by source and category
    create index(:discovery_event_failures, [:source_id, :error_category])

    # Index for pruning old records
    create index(:discovery_event_failures, [:last_seen_at])

    # Unique index for upsert operations (group by source + category + message)
    create unique_index(:discovery_event_failures, [:source_id, :error_category, :error_message],
             name: :discovery_event_failures_unique_idx
           )
  end
end
