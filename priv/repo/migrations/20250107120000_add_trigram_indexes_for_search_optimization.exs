defmodule EventasaurusApp.Repo.Migrations.AddTrigramIndexesForSearchOptimization do
  use Ecto.Migration

  def up do
    # Enable the pg_trgm extension for trigram-based text search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Create GIN indexes with trigram operators for efficient ILIKE searches
    # These are specifically optimized for '%term%' wildcard searches

        # Trigram index for user names (supports ILIKE with wildcards)
    execute """
    CREATE INDEX IF NOT EXISTS users_name_gin_trgm_index
    ON users USING gin (name gin_trgm_ops)
    """

    # Trigram index for user emails (supports ILIKE with wildcards)
    execute """
    CREATE INDEX IF NOT EXISTS users_email_gin_trgm_index
    ON users USING gin (email gin_trgm_ops)
    """

    # Trigram index for usernames (supports ILIKE with wildcards)
    # Only create if username column exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name = 'users' 
                 AND column_name = 'username') THEN
        CREATE INDEX IF NOT EXISTS users_username_gin_trgm_index
        ON users USING gin (username gin_trgm_ops);
      END IF;
    END$$;
    """
  end

  def down do
    # Drop trigram indexes in reverse order
    execute "DROP INDEX IF EXISTS users_username_gin_trgm_index"
    execute "DROP INDEX IF EXISTS users_email_gin_trgm_index"
    execute "DROP INDEX IF EXISTS users_name_gin_trgm_index"

    # Note: We don't drop the pg_trgm extension as other parts of the system might use it
    # execute "DROP EXTENSION IF EXISTS pg_trgm"
  end
end
