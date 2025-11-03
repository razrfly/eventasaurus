defmodule EventasaurusApp.Repo.Migrations.FixUnsplashGalleryIndex do
  use Ecto.Migration

  def change do
    # Drop the old index that tried to index the entire JSONB content
    # This fails with categorized galleries because the data exceeds B-tree size limits
    drop_if_exists index(:cities, [:unsplash_gallery],
      where: "unsplash_gallery IS NOT NULL",
      name: :cities_unsplash_gallery_exists_index
    )

    # Create a new partial index on id instead
    # This is much more efficient and doesn't have size limitations
    # Queries like "WHERE unsplash_gallery IS NOT NULL" will use this index
    create index(:cities, [:id],
      where: "unsplash_gallery IS NOT NULL",
      name: :cities_with_unsplash_gallery_index
    )
  end
end
