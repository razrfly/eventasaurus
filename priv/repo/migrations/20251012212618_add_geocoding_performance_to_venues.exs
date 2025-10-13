defmodule EventasaurusApp.Repo.Migrations.AddGeocodingPerformanceToVenues do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      add :geocoding_performance, :jsonb
    end
  end
end
