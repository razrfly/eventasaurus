defmodule EventasaurusApp.Repo.Migrations.AddVenuesMetadataPartialIndex do
  @moduledoc """
  Add partial index for venues with metadata.

  ## Why This Index Helps

  PlanetScale Insight #5 shows a query reading 2.1M rows from venues with:
  - 5.58% of total runtime
  - P99 latency: 1,089ms
  - Only 3,298 rows returned from 2.1M read

  The query joins venues WHERE metadata IS NOT NULL. A partial index
  dramatically reduces the scan from 2.1M rows to only the ~3K rows
  that have metadata populated.

  ## Index Strategy

  Using a partial index (WHERE metadata IS NOT NULL) rather than a full
  index because:
  1. Only ~0.15% of venue rows have metadata
  2. Partial index is much smaller and faster to scan
  3. Queries filtering on metadata benefit most from this approach

  See GitHub Issue #2537 for full analysis.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Create partial index on venues for rows that have metadata
    # This covers the expensive JOIN pattern seen in query #5
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_venues_with_metadata
      ON venues (id)
      WHERE metadata IS NOT NULL
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS idx_venues_with_metadata
      """
    )
  end
end
