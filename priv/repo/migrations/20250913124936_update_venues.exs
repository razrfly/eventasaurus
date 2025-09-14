defmodule EventasaurusApp.Repo.Migrations.UpdateVenues do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :place_id, :string
      add :source, :string, default: "user"
      add :city_id, references(:cities, on_delete: :nilify_all)
      add :metadata, :map, default: %{}
    end

    create index(:venues, [:place_id])
    create index(:venues, [:city_id])
    create index(:venues, [:source])
  end
end