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
    execute "DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users"
    execute "DROP FUNCTION IF EXISTS public.delete_user_on_auth_delete()"

    # Drop the unique index on supabase_id
    drop_if_exists index(:users, [:supabase_id])

    # Remove the supabase_id column
    alter table(:users) do
      remove :supabase_id
    end
  end

  def down do
    # Re-add the supabase_id column (nullable for rollback since we can't restore data)
    alter table(:users) do
      add :supabase_id, :string, null: true
    end

    # Re-create the unique index
    create unique_index(:users, [:supabase_id])

    # Re-create the trigger and function
    execute """
    CREATE OR REPLACE FUNCTION public.delete_user_on_auth_delete()
    RETURNS TRIGGER AS $$
    BEGIN
      DELETE FROM public.users WHERE supabase_id = OLD.id::text;
      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql SECURITY DEFINER;
    """

    execute """
    CREATE TRIGGER on_auth_user_deleted
      AFTER DELETE ON auth.users
      FOR EACH ROW EXECUTE FUNCTION public.delete_user_on_auth_delete();
    """
  end
end
