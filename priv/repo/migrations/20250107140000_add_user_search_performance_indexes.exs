defmodule EventasaurusApp.Repo.Migrations.AddUserSearchPerformanceIndexes do
  use Ecto.Migration

  def up do
    # Index for efficient ILIKE searches on user names
    # This supports the search_users_for_organizers function that searches by name
    create index(:users, ["lower(name)"], name: :users_name_lower_index,
      comment: "Optimize case-insensitive name searches for user search API")

    # Index for efficient ILIKE searches on user emails
    # While unique_index on email exists, this helps with partial email searches
    create index(:users, ["lower(email)"], name: :users_email_lower_index,
      comment: "Optimize case-insensitive email searches for user search API")

    # Composite index for multi-field searches with privacy filtering
    # This optimizes queries that search across name, username, email with profile_public filter
    # Only create with username and profile_public if columns exist
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name = 'users' 
                 AND column_name = 'username') 
         AND EXISTS (SELECT 1 FROM information_schema.columns 
                     WHERE table_name = 'users' 
                     AND column_name = 'profile_public') THEN
        CREATE INDEX IF NOT EXISTS users_search_composite_index
        ON users (profile_public, lower(name), lower(username), lower(email));
      ELSIF EXISTS (SELECT 1 FROM information_schema.columns 
                    WHERE table_name = 'users' 
                    AND column_name = 'profile_public') THEN
        CREATE INDEX IF NOT EXISTS users_search_composite_index
        ON users (profile_public, lower(name), lower(email));
      ELSE
        CREATE INDEX IF NOT EXISTS users_search_composite_index
        ON users (lower(name), lower(email));
      END IF;
    END$$;
    """

    # Index for efficient event organizer exclusion queries
    # This supports the LEFT JOIN in search_users_for_organizers when excluding existing organizers
    create index(:event_users, [:event_id, :user_id], name: :event_users_exclusion_index,
      comment: "Optimize queries that exclude existing event organizers from search results")

    # Conditional index for active user searches (users with public profiles)
    # This optimizes the most common search case where we're looking for users with public profiles
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name = 'users' 
                 AND column_name = 'username')
         AND EXISTS (SELECT 1 FROM information_schema.columns 
                     WHERE table_name = 'users' 
                     AND column_name = 'profile_public') THEN
        CREATE INDEX IF NOT EXISTS users_public_search_index
        ON users (lower(name), lower(username), lower(email))
        WHERE profile_public = true;
      ELSIF EXISTS (SELECT 1 FROM information_schema.columns 
                    WHERE table_name = 'users' 
                    AND column_name = 'profile_public') THEN
        CREATE INDEX IF NOT EXISTS users_public_search_index
        ON users (lower(name), lower(email))
        WHERE profile_public = true;
      ELSE
        CREATE INDEX IF NOT EXISTS users_public_search_index
        ON users (lower(name), lower(email));
      END IF;
    END$$;
    """

    # Index for user ID exclusion in searches (commonly used to exclude the searching user)
    # This helps with the WHERE NOT u.id = ? conditions
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns 
                 WHERE table_name = 'users' 
                 AND column_name = 'profile_public') THEN
        CREATE INDEX IF NOT EXISTS users_id_profile_index
        ON users (id, profile_public);
      ELSE
        CREATE INDEX IF NOT EXISTS users_id_profile_index
        ON users (id);
      END IF;
    END$$;
    """
  end

  def down do
    # Drop indexes in reverse order
    execute "DROP INDEX IF EXISTS users_id_profile_index"
    execute "DROP INDEX IF EXISTS users_public_search_index"
    drop index(:event_users, [:event_id, :user_id], name: :event_users_exclusion_index)
    execute "DROP INDEX IF EXISTS users_search_composite_index"
    drop index(:users, ["lower(email)"], name: :users_email_lower_index)
    drop index(:users, ["lower(name)"], name: :users_name_lower_index)
  end
end
