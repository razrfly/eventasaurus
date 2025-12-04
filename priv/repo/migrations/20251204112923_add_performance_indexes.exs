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
    # HIGH: Cities Covering Index for Country + Unsplash Gallery Queries
    # ==========================================================================
    # Issue: 63 minutes cumulative execution time, 396ms P99, 2.4 rows read/returned
    # Query: SELECT * FROM cities WHERE country_id = $1 AND unsplash_gallery IS NOT NULL
    # Current: Partial index exists but not covering needed columns
    # Expected improvement: Index-only scans, ~50% latency reduction
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS cities_country_unsplash_covering_idx
      ON cities (country_id)
      INCLUDE (id, name, slug, latitude, longitude, unsplash_gallery)
      WHERE unsplash_gallery IS NOT NULL
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS cities_country_unsplash_covering_idx
      """
    )

    # ==========================================================================
    # HIGH: Public Events ID with Occurrences for Source Join Queries
    # ==========================================================================
    # Issue: 3.5s P99 latency, join only using PK 67% of time
    # Query: SELECT p0.id, p0.occurrences FROM public_events JOIN public_event_sources...
    # Expected improvement: Index-only scans for occurrences column
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS public_events_id_occurrences_idx
      ON public_events (id)
      INCLUDE (occurrences)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS public_events_id_occurrences_idx
      """
    )

    # ==========================================================================
    # MEDIUM: Public Event Sources - Event ID with Metadata for Freshness Queries
    # ==========================================================================
    # Issue: Queries checking metadata->>'recurring' with last_seen_at filter
    # Query: WHERE (metadata->>'recurring' = 'true') AND (last_seen_at >= $1)
    # ==========================================================================
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS public_event_sources_event_metadata_idx
      ON public_event_sources (event_id)
      INCLUDE (metadata, last_seen_at)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS public_event_sources_event_metadata_idx
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
  end
end
