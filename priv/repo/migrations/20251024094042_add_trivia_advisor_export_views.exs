defmodule EventasaurusApp.Repo.Migrations.AddTriviaAdvisorExportViews do
  use Ecto.Migration

  def up do
    # Main trivia events export view for trivia_advisor integration
    execute """
    CREATE VIEW trivia_events_export AS
    SELECT
      pe.id,
      pe.title AS name,

      -- Extract day_of_week from pattern (1=Monday, 7=Sunday)
      CASE (pe.occurrences->'pattern'->'days_of_week'->0)::text
        WHEN '"monday"' THEN 1
        WHEN '"tuesday"' THEN 2
        WHEN '"wednesday"' THEN 3
        WHEN '"thursday"' THEN 4
        WHEN '"friday"' THEN 5
        WHEN '"saturday"' THEN 6
        WHEN '"sunday"' THEN 7
      END AS day_of_week,

      -- Extract start_time from pattern
      (pe.occurrences->'pattern'->>'time')::time AS start_time,

      -- Extract timezone from pattern
      pe.occurrences->'pattern'->>'timezone' AS timezone,

      -- Map frequency to enum
      LOWER(pe.occurrences->'pattern'->>'frequency') AS frequency,

      -- Convert price to cents (handle NULL and free events)
      CASE
        WHEN pes.is_free THEN 0
        WHEN pes.min_price IS NOT NULL THEN (pes.min_price * 100)::integer
        ELSE NULL
      END AS entry_fee_cents,

      -- Get description (prefer English, fallback to any language)
      COALESCE(
        pes.description_translations->>'en',
        pes.description_translations->>
          (SELECT jsonb_object_keys(pes.description_translations) LIMIT 1),
        ''
      ) AS description,

      -- Get hero_image (source image OR first venue image when available)
      COALESCE(
        pes.image_url,
        v.venue_images->0->>'url'
      ) AS hero_image,

      pe.venue_id,

      -- Get first performer (optional)
      (SELECT pep.performer_id
       FROM public_event_performers pep
       WHERE pep.event_id = pe.id
       LIMIT 1) AS performer_id,

      -- Source information
      s.id AS source_id,
      s.name AS source_name,
      s.slug AS source_slug,
      s.logo_url AS source_logo_url,
      s.website_url AS source_website_url,

      -- Venue information (complete)
      v.name AS venue_name,
      v.slug AS venue_slug,
      v.address AS venue_address,
      v.latitude AS venue_latitude,
      v.longitude AS venue_longitude,
      v.metadata->'geocoding'->'raw_response'->>'postcode' AS venue_postcode,
      v.metadata->'geocoding'->'raw_response'->>'place_id' AS venue_place_id,
      v.metadata AS venue_metadata,
      v.venue_images AS venue_images,

      -- City information
      v.city_id,
      c.slug AS city_slug,
      c.name AS city_name,
      c.latitude AS city_latitude,
      c.longitude AS city_longitude,
      c.unsplash_gallery AS city_images,

      -- Country information
      co.id AS country_id,
      co.name AS country_name,
      co.code AS country_code,

      -- Metadata
      pes.source_url,
      pe.inserted_at,
      pe.updated_at

    FROM public_events pe
    INNER JOIN venues v ON v.id = pe.venue_id
    LEFT JOIN cities c ON c.id = v.city_id
    LEFT JOIN countries co ON co.id = c.country_id
    LEFT JOIN LATERAL (
      SELECT * FROM public_event_sources pes2
      WHERE pes2.event_id = pe.id
      ORDER BY pes2.last_seen_at DESC
      LIMIT 1
    ) pes ON true
    INNER JOIN sources s ON s.id = pes.source_id
    WHERE
      -- Filter by trusted trivia sources
      s.slug IN (
        'question-one',
        'quizmeisters',
        'inquizition',
        'speed-quizzing',
        'pubquiz-pl',
        'geeks-who-drink'
      )
      -- Double-check: must have trivia category
      AND EXISTS (
        SELECT 1 FROM public_event_categories pec
        INNER JOIN categories cat ON cat.id = pec.category_id
        WHERE pec.event_id = pe.id AND cat.slug = 'trivia'
      )
      -- Ensure single category only (trivia-only events)
      AND (SELECT COUNT(*) FROM public_event_categories WHERE event_id = pe.id) = 1
      -- Only events with pattern data
      AND pe.occurrences->'pattern' IS NOT NULL
      AND pe.occurrences->'pattern'->'days_of_week' IS NOT NULL
      AND jsonb_array_length(pe.occurrences->'pattern'->'days_of_week') > 0;
    """
  end

  def down do
    execute "DROP VIEW IF EXISTS trivia_events_export"
  end
end
