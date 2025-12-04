defmodule EventasaurusApp.Repo.Migrations.RemoveContainerMembershipsEventIdIndex do
  @moduledoc """
  Remove redundant index public_event_container_memberships_event_id_index.

  This single-column index on event_id is now redundant because we created
  public_event_container_memberships_event_confidence_idx (event_id, confidence_score DESC)
  in migration 20251204112923.

  The composite index serves both:
  - Queries filtering by event_id only (uses leading column)
  - Queries filtering by event_id and ordering by confidence_score

  PlanetScale recommendation #42.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute "DROP INDEX CONCURRENTLY IF EXISTS public_event_container_memberships_event_id_index"
  end

  def down do
    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS public_event_container_memberships_event_id_index ON public_event_container_memberships (event_id)"
  end
end
