defmodule EventasaurusApp.Repo.Migrations.AddMetadataToVenues do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :metadata, :map
    end
  end
end
