defmodule EventasaurusApp.Repo.Migrations.UpdatePollOptionsUniqueConstraintForPlaces do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Drop the existing unique index that only checks title
    execute "DROP INDEX CONCURRENTLY IF EXISTS poll_options_unique_per_user"
    
    # Create two partial unique indexes that align with the duplicate detection logic:
    
    # 1. Unique by (poll_id, place_id) when place_id exists
    # This allows multiple places with the same name but different place_ids
    execute """
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS poll_options_unique_place_per_poll
    ON poll_options (poll_id, (external_data->>'place_id'))
    WHERE (external_data->>'place_id') IS NOT NULL
      AND status = 'active'
      AND deleted_at IS NULL
    """
    
    # 2. Unique by (poll_id, suggested_by_id, lower(title)) when place_id is absent
    # This prevents the same user from suggesting duplicates (case-insensitive)
    # but allows different users to suggest the same option
    execute """
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS poll_options_unique_title_per_user_no_place
    ON poll_options (poll_id, suggested_by_id, lower(title))
    WHERE (external_data->>'place_id') IS NULL
      AND status = 'active'
      AND deleted_at IS NULL
    """
  end

  def down do
    # Drop the new indexes
    execute "DROP INDEX CONCURRENTLY IF EXISTS poll_options_unique_place_per_poll"
    execute "DROP INDEX CONCURRENTLY IF EXISTS poll_options_unique_title_per_user_no_place"
    
    # Recreate the original per-user unique index
    execute """
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS poll_options_unique_per_user
    ON poll_options (poll_id, suggested_by_id, title)
    WHERE deleted_at IS NULL
    """
  end
end