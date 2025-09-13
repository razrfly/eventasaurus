defmodule EventasaurusApp.Repo.Migrations.CreateCities do
  use Ecto.Migration

  def change do
    create table(:cities) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :country_id, references(:countries, on_delete: :restrict), null: false
      add :latitude, :decimal, precision: 10, scale: 6
      add :longitude, :decimal, precision: 10, scale: 6

      timestamps()
    end

    create index(:cities, [:country_id])
    create unique_index(:cities, [:country_id, :slug])
  end
end