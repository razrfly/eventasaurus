defmodule EventasaurusApp.SessionRepo.Migrations.SyncMissingIndexes do
  @moduledoc """
  Idempotent migration to sync missing indexes between local and production.

  Background: Database audit revealed index drift between environments.
  This migration uses IF NOT EXISTS to safely add any missing indexes
  without affecting environments where they already exist.

  Missing from production:
  - cities_name_country_id_index
  - public_event_sources_external_id_source_id_index

  Missing from local:
  - occurrence_planning_event_id_poll_id_index (composite)
  - users_username_gin_trgm_index (trigram search)

  Note: idx_venues_slug vs venues_slug_index is just a naming difference,
  both point to the same column - no action needed.
  """
  use Ecto.Migration

  def up do
    # === Indexes missing from PRODUCTION ===

    # Composite index on cities for name + country lookups
    execute "CREATE INDEX IF NOT EXISTS cities_name_country_id_index ON cities (name, country_id)"

    # Unique composite index for deduplication lookups
    execute "CREATE UNIQUE INDEX IF NOT EXISTS public_event_sources_external_id_source_id_index ON public_event_sources (external_id, source_id)"

    # === Indexes missing from LOCAL ===

    # Composite index for occurrence planning lookups
    execute "CREATE INDEX IF NOT EXISTS occurrence_planning_event_id_poll_id_index ON occurrence_planning (event_id, poll_id)"

    # Trigram index for fuzzy username search (requires pg_trgm extension)
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS users_username_gin_trgm_index ON users USING gin (username gin_trgm_ops)';
      END IF;
    END $$;
    """
  end

  def down do
    # Idempotent migration - don't drop indexes that may have existed before
    :ok
  end
end
