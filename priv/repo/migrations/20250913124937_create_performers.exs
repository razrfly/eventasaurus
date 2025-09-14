defmodule EventasaurusApp.Repo.Migrations.CreatePerformers do
  use Ecto.Migration

  def up do
    create table(:performers) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :image_url, :string
      add :metadata, :map, default: %{}
      add :source_id, :integer

      timestamps()
    end

    create unique_index(:performers, [:slug])
  end

  def down do
    drop table(:performers)
  end
end