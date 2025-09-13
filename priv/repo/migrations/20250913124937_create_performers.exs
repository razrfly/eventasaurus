defmodule EventasaurusApp.Repo.Migrations.CreatePerformers do
  use Ecto.Migration

  def change do
    create table(:performers) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:performers, [:slug])
  end
end