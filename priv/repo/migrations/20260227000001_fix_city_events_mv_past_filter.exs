defmodule EventasaurusApp.Repo.Migrations.FixCityEventsMvPastFilter do
  use Ecto.Migration

  @doc """
  Fix the city_events_mv WHERE clause to include events that started in the
  past but haven't ended yet.

  The v2 MV used `pe.starts_at >= CURRENT_DATE` which excluded events whose
  start time is yesterday but whose end time is still in the future (e.g. a
  movie screening that started at 23:00 last night and ends at 01:00 today).

  The live query (PublicEventsEnhanced) uses:
    (pe.ends_at > NOW() OR (pe.ends_at IS NULL AND pe.starts_at > NOW()))

  This caused a count mismatch: MV showed 151 events vs 170 from the live
  query for the same city, because 16 movie groups with yesterday's screenings
  were excluded.

  Fix: Change the filter to:
    (pe.ends_at IS NOT NULL AND pe.ends_at > NOW())
    OR (pe.ends_at IS NULL AND pe.starts_at >= CURRENT_DATE)

  This keeps the 60-day forward window for efficiency while also including
  events that are currently in progress.

  See: https://github.com/razrfly/eventasaurus/issues/3686
  """

  def up do
    # DROP the old view (brief moment of non-existence; the app falls back to live queries).
    # Immediately replaced with WITH NO DATA so readers get an empty result instead of
    # an error while data is being populated by REFRESH CONCURRENTLY below.
    execute("DROP MATERIALIZED VIEW IF EXISTS city_events_mv")

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
      -- Movie detail columns
      m.movie_runtime,
      m.movie_metadata,
      -- Image columns
      m.movie_poster_url,
      m.movie_backdrop_url,
      primary_source.image_url AS source_image_url,
      -- Source aggregation columns
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
        COALESCE(
          CASE
            WHEN pes.metadata->>'priority' ~ '^[0-9]+$'
            THEN (pes.metadata->>'priority')::integer
            ELSE NULL
          END,
          10
        ) ASC,
        pes.last_seen_at DESC
      LIMIT 1
    ) AS primary_source ON true
    WHERE v.is_public = true
      AND pe.starts_at < CURRENT_DATE + INTERVAL '60 days'
      AND (
        -- Event with end time: keep if it hasn't ended yet
        (pe.ends_at IS NOT NULL AND pe.ends_at > NOW())
        OR
        -- Event without end time: keep if it starts today or later
        (pe.ends_at IS NULL AND pe.starts_at >= CURRENT_DATE)
      )
    WITH NO DATA
    """)

    # Indexes — same as v2
    execute(
      "CREATE UNIQUE INDEX city_events_mv_event_id_idx ON city_events_mv (event_id)"
    )

    execute(
      "CREATE INDEX city_events_mv_city_slug_idx ON city_events_mv (city_slug)"
    )

    execute(
      "CREATE INDEX city_events_mv_city_date_idx ON city_events_mv (city_slug, starts_at)"
    )

    execute(
      "CREATE INDEX city_events_mv_starts_at_idx ON city_events_mv (starts_at)"
    )

    execute("""
    CREATE INDEX city_events_mv_movie_id_idx
    ON city_events_mv (movie_id)
    WHERE movie_id IS NOT NULL
    """)

    execute("""
    CREATE INDEX city_events_mv_source_id_idx
    ON city_events_mv (source_id)
    WHERE aggregate_on_index = true
    """)

    # Populate the view for the first time (non-concurrent, since the view has no data yet).
    # Subsequent refreshes via RefreshCityEventsViewJob use CONCURRENTLY once populated.
    execute("REFRESH MATERIALIZED VIEW city_events_mv")
  end

  def down do
    # Revert to v2 filter (starts_at >= CURRENT_DATE)
    execute("DROP MATERIALIZED VIEW IF EXISTS city_events_mv")

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
      m.movie_id,
      m.movie_title,
      m.movie_slug,
      m.movie_release_date,
      m.movie_runtime,
      m.movie_metadata,
      m.movie_poster_url,
      m.movie_backdrop_url,
      primary_source.image_url AS source_image_url,
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
        COALESCE(
          CASE
            WHEN pes.metadata->>'priority' ~ '^[0-9]+$'
            THEN (pes.metadata->>'priority')::integer
            ELSE NULL
          END,
          10
        ) ASC,
        pes.last_seen_at DESC
      LIMIT 1
    ) AS primary_source ON true
    WHERE pe.starts_at >= CURRENT_DATE
      AND pe.starts_at < CURRENT_DATE + INTERVAL '60 days'
      AND v.is_public = true
    WITH DATA
    """)

    execute(
      "CREATE UNIQUE INDEX city_events_mv_event_id_idx ON city_events_mv (event_id)"
    )

    execute(
      "CREATE INDEX city_events_mv_city_slug_idx ON city_events_mv (city_slug)"
    )

    execute(
      "CREATE INDEX city_events_mv_city_date_idx ON city_events_mv (city_slug, starts_at)"
    )

    execute(
      "CREATE INDEX city_events_mv_starts_at_idx ON city_events_mv (starts_at)"
    )

    execute(
      "CREATE INDEX city_events_mv_movie_id_idx ON city_events_mv (movie_id) WHERE movie_id IS NOT NULL"
    )

    execute(
      "CREATE INDEX city_events_mv_source_id_idx ON city_events_mv (source_id) WHERE aggregate_on_index = true"
    )
  end
end
