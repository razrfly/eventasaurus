defmodule EventasaurusApp.Repo.Migrations.CreatePublicEvents do
  use Ecto.Migration

  def change do
    create table(:public_events) do
      add :external_id, :string
      add :title, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :venue_id, references(:venues, on_delete: :nilify_all)
      add :city_id, references(:cities, on_delete: :restrict), null: false
      add :start_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime
      add :status, :string, default: "active"
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:public_events, [:city_id])
    create index(:public_events, [:venue_id])
    create index(:public_events, [:external_id])
    create index(:public_events, [:start_at])
    create index(:public_events, [:city_id, :start_at])
  end
end