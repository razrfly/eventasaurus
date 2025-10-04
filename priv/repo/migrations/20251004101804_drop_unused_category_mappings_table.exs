defmodule EventasaurusApp.Repo.Migrations.DropUnusedCategoryMappingsTable do
  use Ecto.Migration

  def change do
    # Drop the unused category_mappings table
    # This table was replaced by the YAML-based CategoryMapper system
    # and was never actually used in production code
    drop table(:category_mappings)
  end
end
