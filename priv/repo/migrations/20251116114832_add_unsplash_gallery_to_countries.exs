defmodule EventasaurusApp.Repo.Migrations.AddUnsplashGalleryToCountries do
  use Ecto.Migration

  def change do
    alter table(:countries) do
      add :unsplash_gallery, :jsonb
    end
  end
end
