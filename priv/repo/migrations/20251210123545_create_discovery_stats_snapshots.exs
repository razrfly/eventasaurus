defmodule EventasaurusApp.Repo.Migrations.CreateDiscoveryStatsSnapshots do
  use Ecto.Migration

  def change do
    create table(:discovery_stats_snapshots) do
      add :stats_data, :map, null: false
      add :computed_at, :utc_datetime_usec, null: false
      add :computation_time_ms, :integer
      add :status, :string, default: "completed"

      timestamps()
    end

    # Index for quick lookup of latest snapshot
    create index(:discovery_stats_snapshots, [:computed_at])
  end
end
