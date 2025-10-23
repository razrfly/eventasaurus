defmodule EventasaurusApp.Repo.Migrations.DropDiscoveryEventFailures do
  use Ecto.Migration

  def change do
    drop table(:discovery_event_failures)
  end
end
