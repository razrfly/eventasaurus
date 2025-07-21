defmodule EventasaurusApp.Repo.Migrations.AddVenueTypeToVenues do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :venue_type, :string, null: false, default: "venue"
    end

    # Create an index for faster queries filtering by venue type
    create index(:venues, [:venue_type])
    
    # Execute a backfill to set all existing venues to the "venue" type
    execute "UPDATE venues SET venue_type = 'venue' WHERE venue_type IS NULL", ""
  end
end
