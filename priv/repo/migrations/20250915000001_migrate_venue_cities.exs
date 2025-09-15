defmodule EventasaurusApp.Repo.Migrations.MigrateVenueCities do
  use Ecto.Migration
  require Logger

  def up do
    # The unified discovery architecture already uses city_id foreign keys
    # All venues are created with city_id from the beginning
    # This migration is no longer needed but kept for consistency

    Logger.info("Venue city migration - skipped (venues already use city_id)")
  end

  def down do
    # This is a no-op migration
    Logger.info("Venue city migration rollback - no action needed")
  end
end