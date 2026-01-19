defmodule EventasaurusApp.Repo.Migrations.AddTrigramIndexForVenueSlug do
  @moduledoc """
  Add pg_trgm GIN index on venues.slug for efficient ILIKE pattern matching.

  This addresses a major database egress issue discovered in Phase 0 investigation
  (GitHub issue #3294). The trivia_advisor app (quiz-advisor) uses ILIKE queries
  on venues.slug for legacy URL redirect matching, causing full table scans.

  With pg_trgm GIN index:
  - ILIKE '%pattern%' queries use the index instead of full table scans
  - Estimated reduction: 14M+ rows scanned → index-only lookups
  - Benefits both eventasaurus and trivia_advisor (shared database)

  Note: pg_trgm extension is already enabled in the database.
  """
  use Ecto.Migration

  # Disable DDL transaction for concurrent index creation
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Create GIN index using pg_trgm for efficient ILIKE/pattern matching on venue slugs
    # CONCURRENTLY avoids locking the table during index creation
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS venues_slug_trgm_idx
    ON venues USING gin (slug gin_trgm_ops)
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS venues_slug_trgm_idx")
  end
end
