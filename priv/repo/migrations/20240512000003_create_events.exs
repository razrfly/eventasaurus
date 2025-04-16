defmodule EventasaurusApp.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :title, :string, null: false
      add :tagline, :string
      add :description, :text
      add :start_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime
      add :timezone, :string, null: false
      add :visibility, :string, null: false, default: "public"
      add :slug, :string, null: false
      add :cover_image_url, :string
      add :venue_id, references(:venues, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:events, [:slug])
    create index(:events, [:venue_id])
  end
end
