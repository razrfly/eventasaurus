defmodule EventasaurusApp.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    # Create categories table
    create table(:categories) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :icon, :string
      add :color, :string
      add :display_order, :integer, default: 0

      timestamps()
    end

    create unique_index(:categories, [:slug])
    create index(:categories, [:display_order])

    # Add category_id to public_events
    alter table(:public_events) do
      add :category_id, references(:categories, on_delete: :nilify_all)
    end

    create index(:public_events, [:category_id])
  end
end