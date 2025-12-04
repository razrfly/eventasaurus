defmodule EventasaurusApp.Repo.Migrations.Phase3QueryOptimizations do
  @moduledoc """
  Phase 3 Query Optimizations from Database Performance Roadmap (Issue #2511)

  ## 3a: Fix P99 3.8s Query on public_event_sources

  The existing composite index (source_id, event_id) is good for lookups but
  we add a COVERING index that includes frequently accessed columns to enable
  index-only scans and avoid heap fetches.

  ## 3b: Optimize Geo-spatial Query

  The current GiST index on venues exists but isn't being used effectively
  because queries start from public_events and filter by venue location.

  We add a covering index on public_events(venue_id, starts_at) that helps
  the planner efficiently join and filter.

  ## 3c: Optimize Translation Count Query

  Instead of counting jsonb_object_keys at query time (expensive for 40M rows),
  we add materialized columns for translation counts that are updated on write.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # ==========================================================================
    # 3a: Covering Index for public_event_sources Queries
    # ==========================================================================
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS public_event_sources_source_lookup_covering_idx
    ON public_event_sources (source_id, event_id)
    INCLUDE (last_seen_at, external_id)
    """)

    # ==========================================================================
    # 3b: Supporting Index for Geo-spatial Queries
    # ==========================================================================
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS public_events_venue_starts_covering_idx
    ON public_events (venue_id, starts_at DESC)
    INCLUDE (id)
    """)

    # ==========================================================================
    # 3c: Materialized Translation Counts - Schema Changes
    # Note: Since @disable_ddl_transaction is set, we can run DDL directly
    # ==========================================================================
    execute("""
    ALTER TABLE public_events
    ADD COLUMN IF NOT EXISTS title_translation_count INTEGER DEFAULT 0
    """)

    execute("""
    ALTER TABLE public_event_sources
    ADD COLUMN IF NOT EXISTS description_translation_count INTEGER DEFAULT 0
    """)

    # 3c: Indexes on translation count columns
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS public_events_title_translation_count_idx
    ON public_events (title_translation_count)
    WHERE title_translation_count > 0
    """)

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS public_event_sources_desc_translation_count_idx
    ON public_event_sources (description_translation_count)
    WHERE description_translation_count > 0
    """)

    # 3c: Trigger functions for auto-updating translation counts
    execute("""
    CREATE OR REPLACE FUNCTION update_title_translation_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.title_translations IS NOT NULL AND jsonb_typeof(NEW.title_translations) = 'object' THEN
        NEW.title_translation_count := (SELECT COUNT(*) FROM jsonb_object_keys(NEW.title_translations));
      ELSE
        NEW.title_translation_count := 0;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE OR REPLACE FUNCTION update_description_translation_count()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.description_translations IS NOT NULL AND jsonb_typeof(NEW.description_translations) = 'object' THEN
        NEW.description_translation_count := (SELECT COUNT(*) FROM jsonb_object_keys(NEW.description_translations));
      ELSE
        NEW.description_translation_count := 0;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    # 3c: Create triggers
    execute("DROP TRIGGER IF EXISTS update_title_translation_count_trigger ON public_events")

    execute("""
    CREATE TRIGGER update_title_translation_count_trigger
    BEFORE INSERT OR UPDATE OF title_translations ON public_events
    FOR EACH ROW
    EXECUTE FUNCTION update_title_translation_count()
    """)

    execute("DROP TRIGGER IF EXISTS update_description_translation_count_trigger ON public_event_sources")

    execute("""
    CREATE TRIGGER update_description_translation_count_trigger
    BEFORE INSERT OR UPDATE OF description_translations ON public_event_sources
    FOR EACH ROW
    EXECUTE FUNCTION update_description_translation_count()
    """)

    # 3c: Backfill existing data
    execute("""
    UPDATE public_events
    SET title_translation_count = COALESCE(
      (SELECT COUNT(*) FROM jsonb_object_keys(title_translations)),
      0
    )
    WHERE title_translations IS NOT NULL
      AND jsonb_typeof(title_translations) = 'object'
    """)

    execute("""
    UPDATE public_event_sources
    SET description_translation_count = COALESCE(
      (SELECT COUNT(*) FROM jsonb_object_keys(description_translations)),
      0
    )
    WHERE description_translations IS NOT NULL
      AND jsonb_typeof(description_translations) = 'object'
    """)
  end

  def down do
    # Drop triggers first
    execute("DROP TRIGGER IF EXISTS update_title_translation_count_trigger ON public_events")
    execute("DROP TRIGGER IF EXISTS update_description_translation_count_trigger ON public_event_sources")

    # Drop functions
    execute("DROP FUNCTION IF EXISTS update_title_translation_count()")
    execute("DROP FUNCTION IF EXISTS update_description_translation_count()")

    # Drop indexes
    execute("DROP INDEX CONCURRENTLY IF EXISTS public_events_title_translation_count_idx")
    execute("DROP INDEX CONCURRENTLY IF EXISTS public_event_sources_desc_translation_count_idx")
    execute("DROP INDEX CONCURRENTLY IF EXISTS public_event_sources_source_lookup_covering_idx")
    execute("DROP INDEX CONCURRENTLY IF EXISTS public_events_venue_starts_covering_idx")

    # Drop columns
    execute("ALTER TABLE public_events DROP COLUMN IF EXISTS title_translation_count")
    execute("ALTER TABLE public_event_sources DROP COLUMN IF EXISTS description_translation_count")
  end
end
