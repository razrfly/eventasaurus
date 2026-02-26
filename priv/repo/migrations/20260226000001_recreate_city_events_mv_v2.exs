defmodule EventasaurusApp.Repo.Migrations.RecreateCityEventsMvV2 do
  use Ecto.Migration

  @doc """
  Recreates the city_events_mv materialized view with source aggregation columns.

  PR #3682 deleted the MV fallback system prematurely. This migration restores
  the MV as Tier 3 in the cache chain (base cache → per-filter cache → MV → live query)
  and adds source columns for event group aggregation (pub quizzes, etc.).

  New columns vs old MV:
    - source_id, source_slug, source_name — from sources table via public_event_sources
    - aggregation_type, aggregate_on_index — from sources table (controls grouping)
    - movie_runtime — direct field from movies table
    - movie_metadata — JSONB from movies.metadata (vote_average, genres, tagline)

  See: https://github.com/razrfly/eventasaurus/issues/3686
  """

  def up do
    # Drop existing MV (stale — never dropped in PR #3682)
    execute("DROP MATERIALIZED VIEW IF EXISTS city_events_mv")

    # Recreate with all old columns PLUS source and movie metadata columns
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
      -- Movie identification columns (for movie aggregation)
      m.movie_id,
      m.movie_title,
      m.movie_slug,
      m.movie_release_date,
      -- Movie detail columns (new in v2)
      m.movie_runtime,
      m.movie_metadata,
      -- Image columns
      m.movie_poster_url,
      m.movie_backdrop_url,
      primary_source.image_url AS source_image_url,
      -- Source aggregation columns (new in v2)
      primary_source.source_id AS source_id,
      primary_source.source_slug AS source_slug,
      primary_source.source_name AS source_name,
      primary_source.aggregation_type AS aggregation_type,
      primary_source.aggregate_on_index AS aggregate_on_index
    FROM public_events pe
    JOIN venues v ON v.id = pe.venue_id
    JOIN cities c ON c.id = v.city_id
    LEFT JOIN public_event_categories pec ON pec.event_id = pe.id AND pec.is_primary = true
    LEFT JOIN categories cat ON cat.id = pec.category_id
    -- Movie join: get at most one movie per event to avoid duplicate rows
    LEFT JOIN LATERAL (
      SELECT
        mov.id AS movie_id,
        mov.title AS movie_title,
        mov.slug AS movie_slug,
        mov.release_date AS movie_release_date,
        mov.runtime AS movie_runtime,
        mov.metadata AS movie_metadata,
        mov.poster_url AS movie_poster_url,
        mov.backdrop_url AS movie_backdrop_url
      FROM event_movies em
      JOIN movies mov ON mov.id = em.movie_id
      WHERE em.event_id = pe.id
      ORDER BY mov.id ASC
      LIMIT 1
    ) AS m ON true
    -- Source info + image: get primary source with its image and aggregation config
    LEFT JOIN LATERAL (
      SELECT
        pes.image_url,
        s.id AS source_id,
        s.slug AS source_slug,
        s.name AS source_name,
        s.aggregation_type,
        s.aggregate_on_index
      FROM public_event_sources pes
      JOIN sources s ON s.id = pes.source_id
      WHERE pes.event_id = pe.id
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

    # Indexes — same as old MV plus new source index
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

    # Index for source group aggregation queries (new in v2)
    execute("""
    CREATE INDEX city_events_mv_source_id_idx
    ON city_events_mv (source_id)
    WHERE aggregate_on_index = true
    """)
  end

  def down do
    # This migration cannot be reversed: the original MV shape (migration 20260127105300)
    # used a plain LEFT JOIN for movies which can produce duplicate rows when an event
    # has multiple movies. Restoring that exact query would reintroduce that bug, and
    # the new source aggregation columns (source_id, source_slug, etc.) have no equivalent
    # in the old schema. Roll forward instead of rolling back.
    raise Ecto.MigrationError, message: "irreversible migration"
  end
end
