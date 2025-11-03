defmodule EventasaurusApp.Repo.Migrations.AddUnsplashGalleryGinIndex do
  use Ecto.Migration

  def change do
    # Add GIN index for JSONB performance on unsplash_gallery column
    # This improves query performance for categorized gallery lookups
    create index(:cities, [:unsplash_gallery], using: :gin)
  end
end
