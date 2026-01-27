defmodule EventasaurusApp.Repo.Migrations.AddMovieFieldsToCityEventsMv do
  use Ecto.Migration

  @doc """
  Adds movie_id, movie_title, movie_slug, and movie_release_date to city_events_mv.

  This enables movie aggregation in the CityEventsFallback module, fixing the bug
  where movies showing at multiple venues appear as duplicate cards instead of
  being aggregated into a single AggregatedMovieGroup.

  See: https://github.com/anthropics/eventasaurus/issues/3423
  """

  def up do
    # Drop the existing materialized view and its indexes
    execute("DROP MATERIALIZED VIEW IF EXISTS city_events_mv")

    # Recreate with movie identification columns
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
      -- Movie identification columns (for aggregation)
      m.id AS movie_id,
      m.title AS movie_title,
      m.slug AS movie_slug,
      m.release_date AS movie_release_date,
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

    # Index for movie aggregation queries
    execute("""
    CREATE INDEX city_events_mv_movie_id_idx
    ON city_events_mv (movie_id)
    WHERE movie_id IS NOT NULL
    """)
  end

  def down do
    # Drop the updated materialized view
    execute("DROP MATERIALIZED VIEW IF EXISTS city_events_mv")

    # Recreate the previous version (with image columns but without movie identification columns)
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
