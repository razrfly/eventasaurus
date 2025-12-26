defmodule EventasaurusApp.Repo.Migrations.FixTriviaEventsExportSpatialIndex do
  @moduledoc """
  Fixes the GiST spatial index on trivia_events_export to match the query pattern.

  ## Problem

  The original index was created with:
    CAST(st_setsrid(st_makepoint(venue_longitude, venue_latitude), 4326) AS geography)

  But queries use:
    ST_MakePoint(venue_longitude, venue_latitude)::geography

  PostgreSQL's planner requires EXACT expression match for functional index usage.
  The extra `st_setsrid(..., 4326)` wrapper prevents index matching, even though
  it's semantically equivalent (geography defaults to SRID 4326).

  ## Fix

  Remove the st_setsrid wrapper so the index expression matches the query:
    CAST(st_makepoint(venue_longitude, venue_latitude) AS geography)

  Note: CAST(...) and ::geography are equivalent after parsing.

  ## Expected Impact

  P99 latency should drop from ~1035ms to <50ms for st_dwithin queries.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Drop the old index with wrong expression
    execute "DROP INDEX CONCURRENTLY IF EXISTS trivia_events_export_geog_idx"

    # Create new index with expression matching the query pattern
    # Query uses: ST_MakePoint(venue_longitude, venue_latitude)::geography
    # CAST and :: are equivalent after parsing, so this will match
    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_geog_idx
    ON trivia_events_export
    USING gist (
      CAST(st_makepoint(venue_longitude, venue_latitude) AS geography)
    )
    WHERE venue_latitude IS NOT NULL AND venue_longitude IS NOT NULL
    """
  end

  def down do
    # Restore the original (broken) index expression for rollback
    execute "DROP INDEX CONCURRENTLY IF EXISTS trivia_events_export_geog_idx"

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_geog_idx
    ON trivia_events_export
    USING gist (
      CAST(st_setsrid(st_makepoint(venue_longitude, venue_latitude), 4326) AS geography)
    )
    WHERE venue_latitude IS NOT NULL AND venue_longitude IS NOT NULL
    """
  end
end
