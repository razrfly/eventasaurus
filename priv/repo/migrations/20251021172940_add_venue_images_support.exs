defmodule EventasaurusApp.Repo.Migrations.AddVenueImagesSupport do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :venue_images, :jsonb, default: "[]"
      add :image_enrichment_metadata, :jsonb, default: "{}"
    end

    # Add indices for performance
    create index(:venues, [:venue_images], using: :gin)
    create index(:venues, [:image_enrichment_metadata], using: :gin)
  end
end
