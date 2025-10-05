defmodule EventasaurusApp.Repo.Migrations.AddGooglePlacesMetadataToVenues do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :google_places_metadata, :map
    end
  end
end
