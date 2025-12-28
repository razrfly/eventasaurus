defmodule EventasaurusApp.Repo.Migrations.FixTriviaExportVenueImages do
  use Ecto.Migration

  @moduledoc """
  Fixes the trivia_events_export materialized view to include venue_images.

  The previous migration (20251227162711) removed the venue_images column entirely,
  breaking Quiz Advisor which depends on this column.

  This migration:
  1. Adds venue_images back by querying from cached_images table
  2. Adds venue_image_count for optimization (avoids loading full JSONB array)
  3. Fixes performer_id subquery with ORDER BY for deterministic results
  """

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Step 1: Drop the existing materialized view
    execute "DROP MATERIALIZED VIEW IF EXISTS trivia_events_export"

    # Step 2: Recreate with venue_images, venue_image_count, and fixed performer_id
    execute """
    CREATE MATERIALIZED VIEW trivia_events_export AS
    SELECT
      pe.id,
      pe.title AS name,
      pe.slug AS activity_slug,
      CASE (((pe.occurrences -> 'pattern') -> 'days_of_week') -> 0)::text
        WHEN '"monday"' THEN 1
        WHEN '"tuesday"' THEN 2
        WHEN '"wednesday"' THEN 3
        WHEN '"thursday"' THEN 4
        WHEN '"friday"' THEN 5
        WHEN '"saturday"' THEN 6
        WHEN '"sunday"' THEN 7
        ELSE NULL
      END AS day_of_week,
      ((pe.occurrences -> 'pattern') ->> 'time')::time AS start_time,
      (pe.occurrences -> 'pattern') ->> 'timezone' AS timezone,
      LOWER((pe.occurrences -> 'pattern') ->> 'frequency') AS frequency,
      CASE
        WHEN pes.is_free THEN 0
        WHEN pes.min_price IS NOT NULL THEN (pes.min_price * 100)::integer
        ELSE NULL
      END AS entry_fee_cents,
      COALESCE(
        pes.description_translations ->> 'en',
        pes.description_translations ->> (SELECT jsonb_object_keys(pes.description_translations) LIMIT 1),
        ''
      ) AS description,
      COALESCE(pes.image_url, public.get_entity_image_url('venue', v.id::integer, 0)) AS hero_image,
      pe.venue_id,
      (
        SELECT pep.performer_id
        FROM public_event_performers pep
        WHERE pep.event_id = pe.id
        ORDER BY pep.inserted_at ASC
        LIMIT 1
      ) AS performer_id,
      s.id AS source_id,
      s.name AS source_name,
      s.slug AS source_slug,
      s.logo_url AS source_logo_url,
      s.website_url AS source_website_url,
      v.name AS venue_name,
      v.slug AS venue_slug,
      v.address AS venue_address,
      v.latitude AS venue_latitude,
      v.longitude AS venue_longitude,
      ((v.metadata -> 'geocoding') -> 'raw_response') ->> 'postcode' AS venue_postcode,
      ((v.metadata -> 'geocoding') -> 'raw_response') ->> 'place_id' AS venue_place_id,
      v.metadata AS venue_metadata,
      -- Reconstruct venue_images from cached_images table
      (
        SELECT COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'url', COALESCE(ci.cdn_url, ci.original_url),
              'source', ci.original_source,
              'provider', ci.original_source,
              'metadata', ci.metadata
            ) ORDER BY ci.position
          ),
          '[]'::jsonb
        )
        FROM public.cached_images ci
        WHERE ci.entity_type = 'venue'
          AND ci.entity_id = v.id
          AND ci.status = 'cached'
      ) AS venue_images,
      -- Count of venue images for optimization (avoids loading full JSONB array)
      (
        SELECT COUNT(*)
        FROM public.cached_images ci
        WHERE ci.entity_type = 'venue'
          AND ci.entity_id = v.id
          AND ci.status = 'cached'
      )::integer AS venue_image_count,
      v.city_id,
      c.slug AS city_slug,
      c.name AS city_name,
      c.latitude AS city_latitude,
      c.longitude AS city_longitude,
      c.unsplash_gallery AS city_images,
      co.id AS country_id,
      co.name AS country_name,
      co.code AS country_code,
      pes.source_url,
      pes.last_seen_at,
      pe.inserted_at,
      pe.updated_at
    FROM public_events pe
    JOIN venues v ON v.id = pe.venue_id
    LEFT JOIN cities c ON c.id = v.city_id
    LEFT JOIN countries co ON co.id = c.country_id
    LEFT JOIN LATERAL (
      SELECT
        pes2.id,
        pes2.event_id,
        pes2.source_id,
        pes2.source_url,
        pes2.external_id,
        pes2.last_seen_at,
        pes2.metadata,
        pes2.inserted_at,
        pes2.updated_at,
        pes2.description_translations,
        pes2.image_url,
        pes2.min_price,
        pes2.max_price,
        pes2.currency,
        pes2.is_free
      FROM public_event_sources pes2
      WHERE pes2.event_id = pe.id
      ORDER BY pes2.last_seen_at DESC
      LIMIT 1
    ) pes ON true
    JOIN sources s ON s.id = pes.source_id
    WHERE
      s.slug IN ('question-one', 'quizmeisters', 'inquizition', 'speed-quizzing', 'pubquiz-pl', 'geeks-who-drink')
      AND EXISTS (
        SELECT 1
        FROM public_event_categories pec
        JOIN categories cat ON cat.id = pec.category_id
        WHERE pec.event_id = pe.id AND cat.slug = 'trivia'
      )
      AND (SELECT COUNT(*) FROM public_event_categories WHERE event_id = pe.id) = 1
      AND (pe.occurrences -> 'pattern') IS NOT NULL
      AND (pe.occurrences -> 'pattern') -> 'days_of_week' IS NOT NULL
      AND jsonb_array_length((pe.occurrences -> 'pattern') -> 'days_of_week') > 0
    """

    # Step 3: Recreate all indexes
    execute """
    CREATE UNIQUE INDEX CONCURRENTLY trivia_events_export_id_idx
    ON trivia_events_export (id)
    """

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_geog_idx
    ON trivia_events_export
    USING gist (
      CAST(st_makepoint(venue_longitude, venue_latitude) AS geography)
    )
    WHERE venue_latitude IS NOT NULL AND venue_longitude IS NOT NULL
    """

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_venue_name_idx
    ON trivia_events_export (venue_name)
    """

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_venue_id_idx
    ON trivia_events_export (venue_id)
    """

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_day_of_week_idx
    ON trivia_events_export (day_of_week)
    """
  end

  def down do
    # Revert to the version without venue_images (matches 20251227162711)
    execute "DROP MATERIALIZED VIEW IF EXISTS trivia_events_export"

    execute """
    CREATE MATERIALIZED VIEW trivia_events_export AS
    SELECT
      pe.id,
      pe.title AS name,
      pe.slug AS activity_slug,
      CASE (((pe.occurrences -> 'pattern') -> 'days_of_week') -> 0)::text
        WHEN '"monday"' THEN 1
        WHEN '"tuesday"' THEN 2
        WHEN '"wednesday"' THEN 3
        WHEN '"thursday"' THEN 4
        WHEN '"friday"' THEN 5
        WHEN '"saturday"' THEN 6
        WHEN '"sunday"' THEN 7
        ELSE NULL
      END AS day_of_week,
      ((pe.occurrences -> 'pattern') ->> 'time')::time AS start_time,
      (pe.occurrences -> 'pattern') ->> 'timezone' AS timezone,
      LOWER((pe.occurrences -> 'pattern') ->> 'frequency') AS frequency,
      CASE
        WHEN pes.is_free THEN 0
        WHEN pes.min_price IS NOT NULL THEN (pes.min_price * 100)::integer
        ELSE NULL
      END AS entry_fee_cents,
      COALESCE(
        pes.description_translations ->> 'en',
        pes.description_translations ->> (SELECT jsonb_object_keys(pes.description_translations) LIMIT 1),
        ''
      ) AS description,
      COALESCE(pes.image_url, public.get_entity_image_url('venue', v.id::integer, 0)) AS hero_image,
      pe.venue_id,
      (
        SELECT pep.performer_id
        FROM public_event_performers pep
        WHERE pep.event_id = pe.id
        LIMIT 1
      ) AS performer_id,
      s.id AS source_id,
      s.name AS source_name,
      s.slug AS source_slug,
      s.logo_url AS source_logo_url,
      s.website_url AS source_website_url,
      v.name AS venue_name,
      v.slug AS venue_slug,
      v.address AS venue_address,
      v.latitude AS venue_latitude,
      v.longitude AS venue_longitude,
      ((v.metadata -> 'geocoding') -> 'raw_response') ->> 'postcode' AS venue_postcode,
      ((v.metadata -> 'geocoding') -> 'raw_response') ->> 'place_id' AS venue_place_id,
      v.metadata AS venue_metadata,
      v.city_id,
      c.slug AS city_slug,
      c.name AS city_name,
      c.latitude AS city_latitude,
      c.longitude AS city_longitude,
      c.unsplash_gallery AS city_images,
      co.id AS country_id,
      co.name AS country_name,
      co.code AS country_code,
      pes.source_url,
      pes.last_seen_at,
      pe.inserted_at,
      pe.updated_at
    FROM public_events pe
    JOIN venues v ON v.id = pe.venue_id
    LEFT JOIN cities c ON c.id = v.city_id
    LEFT JOIN countries co ON co.id = c.country_id
    LEFT JOIN LATERAL (
      SELECT
        pes2.id,
        pes2.event_id,
        pes2.source_id,
        pes2.source_url,
        pes2.external_id,
        pes2.last_seen_at,
        pes2.metadata,
        pes2.inserted_at,
        pes2.updated_at,
        pes2.description_translations,
        pes2.image_url,
        pes2.min_price,
        pes2.max_price,
        pes2.currency,
        pes2.is_free
      FROM public_event_sources pes2
      WHERE pes2.event_id = pe.id
      ORDER BY pes2.last_seen_at DESC
      LIMIT 1
    ) pes ON true
    JOIN sources s ON s.id = pes.source_id
    WHERE
      s.slug IN ('question-one', 'quizmeisters', 'inquizition', 'speed-quizzing', 'pubquiz-pl', 'geeks-who-drink')
      AND EXISTS (
        SELECT 1
        FROM public_event_categories pec
        JOIN categories cat ON cat.id = pec.category_id
        WHERE pec.event_id = pe.id AND cat.slug = 'trivia'
      )
      AND (SELECT COUNT(*) FROM public_event_categories WHERE event_id = pe.id) = 1
      AND (pe.occurrences -> 'pattern') IS NOT NULL
      AND (pe.occurrences -> 'pattern') -> 'days_of_week' IS NOT NULL
      AND jsonb_array_length((pe.occurrences -> 'pattern') -> 'days_of_week') > 0
    """

    execute """
    CREATE UNIQUE INDEX CONCURRENTLY trivia_events_export_id_idx
    ON trivia_events_export (id)
    """

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_geog_idx
    ON trivia_events_export
    USING gist (
      CAST(st_makepoint(venue_longitude, venue_latitude) AS geography)
    )
    WHERE venue_latitude IS NOT NULL AND venue_longitude IS NOT NULL
    """

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_venue_name_idx
    ON trivia_events_export (venue_name)
    """

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_venue_id_idx
    ON trivia_events_export (venue_id)
    """

    execute """
    CREATE INDEX CONCURRENTLY trivia_events_export_day_of_week_idx
    ON trivia_events_export (day_of_week)
    """
  end
end
