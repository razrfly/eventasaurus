defmodule EventasaurusApp.Repo.Migrations.RemoveUnusedCachedImagesColumns do
  use Ecto.Migration

  def change do
    alter table(:cached_images) do
      # These columns were never populated (0% usage across 11,000+ records)
      # Removing to clean up the schema
      remove(:width, :integer)
      remove(:height, :integer)
    end
  end
end
