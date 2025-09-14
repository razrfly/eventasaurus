defmodule EventasaurusApp.Repo.Migrations.AddCategoryToPublicEvents do
  use Ecto.Migration

  def change do
    alter table(:public_events) do
      add :category_id, references(:categories, on_delete: :nilify_all)
    end

    create index(:public_events, [:category_id])
  end
end