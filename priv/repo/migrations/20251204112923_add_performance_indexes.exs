defmodule EventasaurusApp.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # ==========================================================================
    # CRITICAL: Container Memberships Composite Index
    # ==========================================================================
    # Issue: Query filters by event_id but only has index on confidence_score
    # Impact: Reading 25,345 rows to return 1 row (0.04% index usage)
    # Query: SELECT container_id WHERE event_id = $1 ORDER BY confidence_score DESC
    # Expected improvement: 25,000x reduction in rows scanned
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS public_event_container_memberships_event_confidence_idx
      ON public_event_container_memberships (event_id, confidence_score DESC)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS public_event_container_memberships_event_confidence_idx
      """
    )

    # ==========================================================================
    # HIGH: Cities Partial Index for Country + Unsplash Gallery Queries
    # ==========================================================================
    # Issue: 63 minutes cumulative execution time, 396ms P99, 2.4 rows read/returned
    # Query: SELECT * FROM cities WHERE country_id = $1 AND unsplash_gallery IS NOT NULL
    # Note: Cannot use INCLUDE with unsplash_gallery JSONB - exceeds 8191 byte limit
    # Using partial index to filter to only rows with unsplash_gallery
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS cities_country_unsplash_covering_idx
      ON cities (country_id)
      INCLUDE (id, name, slug, latitude, longitude)
      WHERE unsplash_gallery IS NOT NULL
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS cities_country_unsplash_covering_idx
      """
    )

    # ==========================================================================
    # HIGH: Public Events ID with Occurrences - SKIPPED
    # ==========================================================================
    # Issue: 3.5s P99 latency, join only using PK 67% of time
    # Query: SELECT p0.id, p0.occurrences FROM public_events JOIN public_event_sources...
    # SKIPPED: occurrences JSONB column exceeds btree index size limit (2704 bytes)
    # The primary key index on id already provides good performance for joins
    # Clean up any partially created invalid index from previous failed attempt
    # ==========================================================================
    execute(
      """
      DROP INDEX CONCURRENTLY IF EXISTS public_events_id_occurrences_idx
      """,
      """
      SELECT 1
      """
    )

    # ==========================================================================
    # MEDIUM: Public Event Sources - Recurring Events with Last Seen Filter
    # ==========================================================================
    # Issue: Queries checking metadata->>'recurring' with last_seen_at filter
    # Query: WHERE (metadata->>'recurring' = 'true') AND (last_seen_at >= $1)
    # Expression index on the JSONB path for efficient filtering
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS public_event_sources_recurring_last_seen_idx
      ON public_event_sources ((metadata->>'recurring'), last_seen_at)
      WHERE metadata->>'recurring' IS NOT NULL
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS public_event_sources_recurring_last_seen_idx
      """
    )

    # ==========================================================================
    # MEDIUM: Public Events - Ends At + Starts At for Time Range Queries
    # ==========================================================================
    # Issue: Complex OR conditions on time filtering prevent efficient index use
    # Query: WHERE (ends_at > X) OR (ends_at IS NULL AND starts_at > Y)
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS public_events_time_range_idx
      ON public_events (ends_at, starts_at)
      INCLUDE (venue_id)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS public_events_time_range_idx
      """
    )

    # ==========================================================================
    # MEDIUM: GIN Index for Description Translations JSONB
    # ==========================================================================
    # Issue: Queries using jsonb_object_keys/jsonb_each_text on description_translations
    # Query: SELECT count(*) FROM jsonb_object_keys(description_translations)
    # Note: title_translations already has GIN index, this covers description_translations
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS public_event_sources_description_translations_gin_idx
      ON public_event_sources USING GIN (description_translations)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS public_event_sources_description_translations_gin_idx
      """
    )

    # ==========================================================================
    # MEDIUM: Composite Index for Public Event Categories Lookups
    # ==========================================================================
    # Issue: LEFT JOIN + IS NULL pattern reading 8,877 rows per returned
    # Query: LEFT JOIN public_event_categories ON ... WHERE category_id IS NULL
    # This index helps the anti-join pattern perform better
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS public_event_categories_event_category_lookup_idx
      ON public_event_categories (event_id)
      INCLUDE (category_id)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS public_event_categories_event_category_lookup_idx
      """
    )
  end
end
