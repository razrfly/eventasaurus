defmodule EventasaurusApp.Repo.Migrations.CreatePublicEvents do
  use Ecto.Migration

  def change do
    create table(:public_events) do
      add :title, :string, null: false
      add :slug, :string
      add :description, :text
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime
      add :external_id, :string
      add :ticket_url, :string
      add :min_price, :decimal
      add :max_price, :decimal
      add :currency, :string
      add :metadata, :map, default: %{}
      add :venue_id, references(:venues, on_delete: :nilify_all)

      timestamps()
    end

    create index(:public_events, [:venue_id])
    create index(:public_events, [:starts_at])
    create unique_index(:public_events, [:slug])
    create unique_index(:public_events, [:external_id])
  end
end