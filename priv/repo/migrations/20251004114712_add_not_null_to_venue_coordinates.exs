defmodule EventasaurusApp.Repo.Migrations.AddNotNullToVenueCoordinates do
  use Ecto.Migration

  def up do
    # First verify no NULL values exist
    # All current venues are physical and should have coordinates
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM venues WHERE latitude IS NULL OR longitude IS NULL) THEN
        RAISE EXCEPTION 'Cannot add NOT NULL constraint: venues table contains NULL coordinates';
      END IF;
    END $$;
    """

    # Drop the view that depends on the latitude/longitude columns
    execute "DROP VIEW IF EXISTS public_events_view"

    # Add NOT NULL constraints for latitude and longitude
    # This enforces data integrity at the database level
    # All venues are physical locations and require coordinates
    alter table(:venues) do
      modify :latitude, :float, null: false
      modify :longitude, :float, null: false
    end

    # Recreate the view
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
      pes.min_price,
      pes.max_price,
      pes.currency,
      pes.is_free,
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
    # Drop the view
    execute "DROP VIEW IF EXISTS public_events_view"

    # Revert to allowing NULL coordinates
    alter table(:venues) do
      modify :latitude, :float, null: true
      modify :longitude, :float, null: true
    end

    # Recreate the view
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
      pes.min_price,
      pes.max_price,
      pes.currency,
      pes.is_free,
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
