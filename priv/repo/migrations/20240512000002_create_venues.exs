defmodule EventasaurusApp.Repo.Migrations.CreateVenues do
  use Ecto.Migration

  def change do
    create table(:venues) do
      add :name, :string, null: false
      add :address, :string
      add :city, :string
      add :state, :string
      add :country, :string
      add :latitude, :float
      add :longitude, :float

      timestamps()
    end
  end
end
