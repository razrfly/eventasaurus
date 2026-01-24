defmodule EventasaurusApp.Repo.Migrations.AddImagesToCityEventsMv do
  use Ecto.Migration

  @doc """
  Adds image columns to the city_events_mv materialized view.

  This resolves Issue #3376 where city pages show blank images when the
  Cachex cache misses and falls back to the materialized view.

  Image priority follows the same logic as PublicEventsEnhanced.get_cover_image_url:
  1. Movie backdrop/poster (for movie events)
  2. Source image (from public_event_sources)
  3. Falls back to NULL (city Unsplash will be used in application code)

  The view uses a lateral subquery to get the primary source's image URL.
  """

  def up do
    # Drop the existing materialized view and its indexes
    execute("DROP MATERIALIZED VIEW IF EXISTS city_events_mv")

    # Recreate with image columns
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
      cat.slug AS category_slug,
      -- Image columns
      m.poster_url AS movie_poster_url,
      m.backdrop_url AS movie_backdrop_url,
      primary_source.image_url AS source_image_url
    FROM public_events pe
    JOIN venues v ON v.id = pe.venue_id
    JOIN cities c ON c.id = v.city_id
    LEFT JOIN public_event_categories pec ON pec.event_id = pe.id AND pec.is_primary = true
    LEFT JOIN categories cat ON cat.id = pec.category_id
    -- Movie join: get first movie for this event (most events have 0 or 1 movie)
    LEFT JOIN event_movies em ON em.event_id = pe.id
    LEFT JOIN movies m ON m.id = em.movie_id
    -- Source image: get image from primary source using a lateral subquery
    LEFT JOIN LATERAL (
      SELECT pes.image_url
      FROM public_event_sources pes
      WHERE pes.event_id = pe.id
        AND pes.image_url IS NOT NULL
      ORDER BY
        -- Priority from metadata (lower is better)
        COALESCE(
          CASE
            WHEN pes.metadata->>'priority' ~ '^[0-9]+$'
            THEN (pes.metadata->>'priority')::integer
            ELSE NULL
          END,
          10
        ) ASC,
        -- Newest source first
        pes.last_seen_at DESC
      LIMIT 1
    ) AS primary_source ON true
    WHERE pe.starts_at >= CURRENT_DATE
      AND pe.starts_at < CURRENT_DATE + INTERVAL '60 days'
      AND v.is_public = true
    WITH DATA
    """)

    # Recreate indexes
    execute("""
    CREATE UNIQUE INDEX city_events_mv_event_id_idx
    ON city_events_mv (event_id)
    """)

    execute("""
    CREATE INDEX city_events_mv_city_slug_idx
    ON city_events_mv (city_slug)
    """)

    execute("""
    CREATE INDEX city_events_mv_city_date_idx
    ON city_events_mv (city_slug, starts_at)
    """)

    execute("""
    CREATE INDEX city_events_mv_starts_at_idx
    ON city_events_mv (starts_at)
    """)
  end

  def down do
    # Drop the updated materialized view
    execute("DROP MATERIALIZED VIEW IF EXISTS city_events_mv")

    # Recreate the original view without image columns
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

    # Recreate original indexes
    execute("""
    CREATE UNIQUE INDEX city_events_mv_event_id_idx
    ON city_events_mv (event_id)
    """)

    execute("""
    CREATE INDEX city_events_mv_city_slug_idx
    ON city_events_mv (city_slug)
    """)

    execute("""
    CREATE INDEX city_events_mv_city_date_idx
    ON city_events_mv (city_slug, starts_at)
    """)

    execute("""
    CREATE INDEX city_events_mv_starts_at_idx
    ON city_events_mv (starts_at)
    """)
  end
end
