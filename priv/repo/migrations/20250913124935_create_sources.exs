defmodule EventasaurusApp.Repo.Migrations.CreateSources do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :website_url, :string
      add :priority, :integer, default: 50
      add :is_active, :boolean, default: true
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:sources, [:slug])
    create index(:sources, [:is_active])
  end
end