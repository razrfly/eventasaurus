defmodule EventasaurusApp.Repo.Migrations.AddAuthUsersForeignKey do
  use Ecto.Migration

  def up do
    # Skip this migration in test environment since auth schema doesn't exist there
    if Code.ensure_loaded?(Mix) and Mix.env() == :test do
      :skip
    else
      # Since we can't create a direct FK between UUID and string,
      # we'll use the official Supabase approach: database triggers

      # Function to delete public user when auth user is deleted
      execute """
      CREATE OR REPLACE FUNCTION public.delete_user_on_auth_delete()
      RETURNS TRIGGER AS $$
      BEGIN
        DELETE FROM public.users WHERE supabase_id = OLD.id::text;
        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql SECURITY DEFINER;
      """

      # Trigger on auth.users deletion
      execute """
      CREATE TRIGGER on_auth_user_deleted
        AFTER DELETE ON auth.users
        FOR EACH ROW EXECUTE FUNCTION public.delete_user_on_auth_delete();
      """
    end
  end

  def down do
    if Mix.env() != :test do
      # Remove the trigger and function
      execute "DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users"
      execute "DROP FUNCTION IF EXISTS public.delete_user_on_auth_delete()"
    end
  end
end
