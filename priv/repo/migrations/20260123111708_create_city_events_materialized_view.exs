defmodule EventasaurusApp.Repo.Migrations.CreateCityEventsMaterializedView do
  use Ecto.Migration

  @doc """
  Creates a materialized view for city page event data.

  This view denormalizes event data for fast city page queries, serving as a
  guaranteed fallback when Cachex misses. It ensures that event counts and
  event lists always come from the same data source, preventing the UX bug
  where counts show "79 events" but the grid shows "No Events Found".

  The view should be refreshed hourly via RefreshCityEventsViewJob.

  See: https://github.com/anthropics/eventasaurus/issues/3373
  """

  def up do
    # Create the materialized view with denormalized event data
    execute("""
    CREATE MATERIALIZED VIEW city_events_mv AS
    SELECT
      pe.id AS event_id,
      pe.title,
      pe.slug AS event_slug,
      pe.starts_at,
      pe.ends_at,
      pe.occurrences,
      c.id AS city_id,
      c.slug AS city_slug,
      c.name AS city_name,
      c.timezone AS city_timezone,
      v.id AS venue_id,
      v.name AS venue_name,
      v.slug AS venue_slug,
      v.latitude AS venue_lat,
      v.longitude AS venue_lng,
      v.is_public AS venue_is_public,
      cat.id AS category_id,
      cat.name AS category_name,
      cat.slug AS category_slug
    FROM public_events pe
    JOIN venues v ON v.id = pe.venue_id
    JOIN cities c ON c.id = v.city_id
    LEFT JOIN public_event_categories pec ON pec.event_id = pe.id AND pec.is_primary = true
    LEFT JOIN categories cat ON cat.id = pec.category_id
    WHERE pe.starts_at >= CURRENT_DATE
      AND pe.starts_at < CURRENT_DATE + INTERVAL '60 days'
      AND v.is_public = true
    WITH DATA
    """)

    # Unique index required for REFRESH MATERIALIZED VIEW CONCURRENTLY
    execute("""
    CREATE UNIQUE INDEX city_events_mv_event_id_idx
    ON city_events_mv (event_id)
    """)

    # Index for city page queries - most common access pattern
    execute("""
    CREATE INDEX city_events_mv_city_slug_idx
    ON city_events_mv (city_slug)
    """)

    # Composite index for date-filtered city queries
    execute("""
    CREATE INDEX city_events_mv_city_date_idx
    ON city_events_mv (city_slug, starts_at)
    """)

    # Index for date-based counting (used by date filter badges)
    execute("""
    CREATE INDEX city_events_mv_starts_at_idx
    ON city_events_mv (starts_at)
    """)
  end

  def down do
    execute("DROP MATERIALIZED VIEW IF EXISTS city_events_mv")
  end
end
