defmodule EventasaurusApp.Repo.Migrations.AddIdxPerformersOnLowerName do
  @moduledoc """
  Fix PlanetScale Insight #45: Add index with the exact name PlanetScale recommends.

  Previous migration (20251218081953) created `performers_lower_name_index` but
  PlanetScale recommends `idx_performers_on_lower_name`. This migration:
  1. Drops the incorrectly-named index if it exists
  2. Creates the index with the exact recommended name

  Uses CONCURRENTLY to avoid locking the table during creation.
  Uses IF NOT EXISTS/IF EXISTS for idempotency.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Drop the incorrectly named index from previous migration if it exists
    execute "DROP INDEX CONCURRENTLY IF EXISTS performers_lower_name_index"

    # Create with the exact name PlanetScale recommends
    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_performers_on_lower_name ON performers (lower(name))"
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_performers_on_lower_name"
  end
end
