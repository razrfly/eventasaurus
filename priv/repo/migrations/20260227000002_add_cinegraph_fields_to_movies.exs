defmodule EventasaurusApp.Repo.Migrations.AddCinegraphFieldsToMovies do
  use Ecto.Migration

  def change do
    alter table(:movies) do
      add :cinegraph_data, :map
      add :cinegraph_synced_at, :utc_datetime
    end
  end
end
