defmodule EventasaurusApp.Repo.Migrations.UpgradeObanJobsToV12 do
  @moduledoc """
  Upgrade Oban schema to v12.

  This migration:
  - Removes insert triggers from oban_jobs table
  - Relaxes priority column constraint to allow values 0-9

  Required for Oban 2.17+ to prevent duplicate insert notifications.
  See: https://hexdocs.pm/oban/2.17.0/upgrading.html
  """
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 12)
  def down, do: Oban.Migration.down(version: 12)
end
