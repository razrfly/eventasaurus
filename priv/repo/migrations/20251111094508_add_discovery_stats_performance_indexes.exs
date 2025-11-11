defmodule EventasaurusApp.Repo.Migrations.AddDiscoveryStatsPerformanceIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # ===== Sources table indexes =====
    # Optimizes: count_events_for_source, get_events_by_city_for_source
    create_if_not_exists index(:sources, [:slug], concurrently: true)

    # ===== Public Event Sources table indexes =====
    # Optimizes: count_events_for_source JOIN queries
    create_if_not_exists index(:public_event_sources, [:source_id], concurrently: true)
    create_if_not_exists index(:public_event_sources, [:event_id], concurrently: true)
    # Composite index for optimal JOIN performance
    create_if_not_exists index(:public_event_sources, [:source_id, :event_id],
      concurrently: true,
      name: :public_event_sources_source_event_idx
    )

    # ===== Public Events table indexes =====
    # Optimizes: count_events_this_week, calculate_city_change time-based queries
    create_if_not_exists index(:public_events, [:inserted_at], concurrently: true)
    create_if_not_exists index(:public_events, [:venue_id], concurrently: true)
    # Composite index for time + venue queries
    create_if_not_exists index(:public_events, [:venue_id, :inserted_at],
      concurrently: true,
      name: :public_events_venue_time_idx
    )

    # ===== Venues table indexes =====
    # Optimizes: get_city_performance, calculate_city_change JOIN queries
    create_if_not_exists index(:venues, [:city_id], concurrently: true)

    # ===== Cities table indexes =====
    # Optimizes: city lookups and clustering operations
    create_if_not_exists index(:cities, [:slug], concurrently: true)
    create_if_not_exists index(:cities, [:name], concurrently: true)

    # ===== Oban Jobs table indexes =====
    # Optimizes: DiscoveryStatsCollector queries

    # Basic indexes for state and worker filtering
    create_if_not_exists index(:oban_jobs, [:worker], concurrently: true)
    create_if_not_exists index(:oban_jobs, [:state], concurrently: true)

    # Composite index for common worker+state queries
    create_if_not_exists index(:oban_jobs, [:worker, :state],
      concurrently: true,
      name: :oban_jobs_worker_state_idx
    )

    # Timestamp indexes for ordering and filtering
    create_if_not_exists index(:oban_jobs, [:completed_at], concurrently: true)
    create_if_not_exists index(:oban_jobs, [:discarded_at], concurrently: true)
    create_if_not_exists index(:oban_jobs, [:attempted_at], concurrently: true)

    # JSONB GIN indexes for metadata queries
    # Optimizes: meta->>'status' queries
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS oban_jobs_meta_status_idx
      ON oban_jobs USING GIN ((meta -> 'status'))
      """,
      """
      DROP INDEX IF EXISTS oban_jobs_meta_status_idx
      """
    )

    # Optimizes: args->>'city_id' queries
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS oban_jobs_args_city_id_idx
      ON oban_jobs USING GIN ((args -> 'city_id'))
      """,
      """
      DROP INDEX IF EXISTS oban_jobs_args_city_id_idx
      """
    )

    # Composite index for worker + state + timestamp (most common query pattern)
    create_if_not_exists index(:oban_jobs,
      [:worker, :state, :completed_at],
      concurrently: true,
      name: :oban_jobs_worker_state_completed_idx
    )
  end
end
