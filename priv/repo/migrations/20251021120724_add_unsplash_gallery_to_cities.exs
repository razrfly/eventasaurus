defmodule EventasaurusApp.Repo.Migrations.AddUnsplashGalleryToCities do
  use Ecto.Migration

  def change do
    alter table(:cities) do
      add :unsplash_gallery, :map
    end

    # Index for quick lookup of cities with galleries
    create index(:cities, [:unsplash_gallery],
      where: "unsplash_gallery IS NOT NULL",
      name: :cities_unsplash_gallery_exists_index
    )
  end
end
