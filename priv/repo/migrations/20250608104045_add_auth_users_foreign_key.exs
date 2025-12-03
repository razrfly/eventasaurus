defmodule EventasaurusApp.Repo.Migrations.AddAuthUsersForeignKey do
  use Ecto.Migration

  # DEPRECATED: This migration was for Supabase auth.users integration.
  # Since we've migrated to Clerk for authentication and local Postgres for development,
  # the auth.users schema no longer exists. This migration is now a no-op.

  def up do
    # No-op: Supabase auth.users schema doesn't exist in local Postgres or PlanetScale
    :ok
  end

  def down do
    # No-op
    :ok
  end
end
