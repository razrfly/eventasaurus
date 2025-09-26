defmodule EventasaurusApp.Repo.Migrations.UpdatePublicEventsViewForSourcePrices do
  use Ecto.Migration

  def up do
    # Drop the existing view
    execute "DROP VIEW IF EXISTS public_events_view"

    # Recreate the view with price data coming from public_event_sources
    execute """
    CREATE VIEW public_events_view AS
    SELECT
      pe.id,
      pe.slug,
      pe.title,
      pe.title_translations,
      pe.starts_at,
      pe.ends_at,
      pe.venue_id,
      pe.category_id,
      -- Price fields now come from the source, not the event
      pes.min_price,
      pes.max_price,
      pes.currency,
      pes.is_free,
      pe.ticket_url,
      pe.inserted_at,
      pe.updated_at,
      pes.id AS source_id,
      pes.description_translations,
      pes.image_url,
      pes.source_url,
      pes.external_id,
      pes.metadata AS source_metadata,
      pes.last_seen_at AS source_last_seen_at,
      v.name AS venue_name,
      v.slug AS venue_slug,
      v.address AS venue_address,
      v.latitude AS venue_latitude,
      v.longitude AS venue_longitude,
      v.venue_type,
      c.id AS city_id,
      c.name AS city_name,
      c.slug AS city_slug,
      co.id AS country_id,
      co.name AS country_name,
      co.code AS country_code,
      cat.name AS category_name,
      cat.slug AS category_slug,
      cat.translations AS category_translations,
      cat.icon AS category_icon,
      cat.color AS category_color
    FROM public_events pe
    LEFT JOIN LATERAL (
      SELECT *
      FROM public_event_sources
      WHERE event_id = pe.id
      ORDER BY
        COALESCE(
          CASE
            WHEN metadata->>'priority' ~ '^[0-9]+$'
            THEN (metadata->>'priority')::integer
            ELSE NULL
          END,
          10
        ),
        last_seen_at DESC
      LIMIT 1
    ) pes ON true
    LEFT JOIN venues v ON pe.venue_id = v.id
    LEFT JOIN cities c ON v.city_id = c.id
    LEFT JOIN countries co ON c.country_id = co.id
    LEFT JOIN categories cat ON pe.category_id = cat.id
    """
  end

  def down do
    # Drop the updated view
    execute "DROP VIEW IF EXISTS public_events_view"

    # Recreate the original view with prices from public_events
    execute """
    CREATE VIEW public_events_view AS
    SELECT
      pe.id,
      pe.slug,
      pe.title,
      pe.title_translations,
      pe.starts_at,
      pe.ends_at,
      pe.venue_id,
      pe.category_id,
      -- Original: prices from public_events
      pe.min_price,
      pe.max_price,
      pe.currency,
      pe.ticket_url,
      pe.inserted_at,
      pe.updated_at,
      pes.id AS source_id,
      pes.description_translations,
      pes.image_url,
      pes.source_url,
      pes.external_id,
      pes.metadata AS source_metadata,
      pes.last_seen_at AS source_last_seen_at,
      v.name AS venue_name,
      v.slug AS venue_slug,
      v.address AS venue_address,
      v.latitude AS venue_latitude,
      v.longitude AS venue_longitude,
      v.venue_type,
      c.id AS city_id,
      c.name AS city_name,
      c.slug AS city_slug,
      co.id AS country_id,
      co.name AS country_name,
      co.code AS country_code,
      cat.name AS category_name,
      cat.slug AS category_slug,
      cat.translations AS category_translations,
      cat.icon AS category_icon,
      cat.color AS category_color
    FROM public_events pe
    LEFT JOIN LATERAL (
      SELECT *
      FROM public_event_sources
      WHERE event_id = pe.id
      ORDER BY
        COALESCE(
          CASE
            WHEN metadata->>'priority' ~ '^[0-9]+$'
            THEN (metadata->>'priority')::integer
            ELSE NULL
          END,
          10
        ),
        last_seen_at DESC
      LIMIT 1
    ) pes ON true
    LEFT JOIN venues v ON pe.venue_id = v.id
    LEFT JOIN cities c ON v.city_id = c.id
    LEFT JOIN countries co ON c.country_id = co.id
    LEFT JOIN categories cat ON pe.category_id = cat.id
    """
  end
end