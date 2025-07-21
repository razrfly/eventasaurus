defmodule EventasaurusApp.Repo.Migrations.AddVenueFieldsToGroups do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      add :venue_name, :string
      add :venue_address, :string
      add :venue_city, :string
      add :venue_state, :string
      add :venue_country, :string
      add :venue_latitude, :float
      add :venue_longitude, :float
    end

    # Add indexes for location-based queries
    create index(:groups, :venue_city)
    create index(:groups, :venue_state)
    create index(:groups, [:venue_latitude, :venue_longitude])
  end
end
