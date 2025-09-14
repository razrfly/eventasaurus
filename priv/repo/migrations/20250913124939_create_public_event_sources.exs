defmodule EventasaurusApp.Repo.Migrations.CreatePublicEventSources do
  use Ecto.Migration

  def change do
    create table(:public_event_sources) do
      add :event_id, references(:public_events, on_delete: :delete_all), null: false
      add :source_id, references(:sources, on_delete: :restrict), null: false
      add :source_url, :string
      add :external_id, :string
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false
      add :is_primary, :boolean, default: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:public_event_sources, [:event_id, :source_id])
    create index(:public_event_sources, [:source_id, :external_id])
  end
end