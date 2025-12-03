defmodule EventasaurusApp.Repo.Migrations.RemoveSupabaseIdColumn do
  use Ecto.Migration

  @moduledoc """
  Removes the supabase_id column and related infrastructure from the users table.

  With the migration to Clerk authentication, supabase_id is no longer used.
  Users are now identified by their integer primary key (users.id), which is
  stored in Clerk as external_id and included in JWT claims as userId.

  This migration:
  1. Drops the trigger that cascaded deletes from auth.users
  2. Drops the function used by that trigger
  3. Drops the unique index on supabase_id
  4. Removes the supabase_id column entirely
  """

  def up do
    # Drop the Supabase auth cascade trigger and function (if they exist)
    # These were created in 20250608104045_add_auth_users_foreign_key.exs
    # Note: auth.users schema only exists in Supabase, not in local Postgres or PlanetScale
    # We use a PL/pgSQL block to safely check if the schema exists before dropping
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth') THEN
        DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users;
      END IF;
    END $$;
    """
    execute "DROP FUNCTION IF EXISTS public.delete_user_on_auth_delete()"

    # Drop the unique index on supabase_id
    drop_if_exists index(:users, [:supabase_id])

    # Remove the supabase_id column (only if it exists)
    # In fresh local databases, this column may not exist
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'supabase_id') THEN
        ALTER TABLE users DROP COLUMN supabase_id;
      END IF;
    END $$;
    """
  end

  def down do
    # Re-add the supabase_id column (nullable for rollback since we can't restore data)
    # Only add if it doesn't already exist
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'supabase_id') THEN
        ALTER TABLE users ADD COLUMN supabase_id VARCHAR NULL;
      END IF;
    END $$;
    """

    # Re-create the unique index (if column exists)
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'supabase_id') THEN
        CREATE UNIQUE INDEX IF NOT EXISTS users_supabase_id_index ON users(supabase_id);
      END IF;
    END $$;
    """

    # Skip re-creating the trigger - auth.users schema doesn't exist in local Postgres or PlanetScale
    # The trigger was only relevant for Supabase environments
  end
end
