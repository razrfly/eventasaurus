defmodule EventasaurusApp.Repo.Migrations.UpgradeObanJobsToV13 do
  @moduledoc """
  Upgrade Oban schema to v13.

  This migration adds compound indexes for cancelled_at and discarded_at columns
  to significantly improve Oban.Plugins.Pruner performance when cleaning up
  cancelled and discarded jobs.

  Required for Oban 2.20+ for optimal Pruner performance.
  See: https://hexdocs.pm/oban/changelog.html
  """
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 13)
  def down, do: Oban.Migration.down(version: 13)
end
