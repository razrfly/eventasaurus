defmodule EventasaurusApp.Repo.Migrations.CreateCountries do
  use Ecto.Migration

  def change do
    create table(:countries) do
      add :name, :string, null: false
      add :code, :string, size: 2, null: false
      add :slug, :string, null: false

      timestamps()
    end

    create unique_index(:countries, [:code])
    create unique_index(:countries, [:slug])
  end
end