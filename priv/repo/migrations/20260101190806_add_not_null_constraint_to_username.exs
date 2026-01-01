defmodule EventasaurusApp.Repo.Migrations.AddNotNullConstraintToUsername do
  @moduledoc """
  Add NOT NULL constraint to username column.

  This migration should only be run after the backfill migration
  (20260101170107_backfill_usernames) has successfully populated
  all NULL usernames.

  Prerequisites verified:
  - All 320 users have usernames (0 NULL values)
  - Unique index on lower(username) already exists
  """
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :username, :string, null: false
    end
  end
end
