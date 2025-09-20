defmodule EventasaurusApp.Repo.Migrations.CreatePublicEventsComprehensiveView do
  use Ecto.Migration

  def up do
    # Create a single comprehensive view that includes all needed data
    execute """
    CREATE OR REPLACE VIEW public_events_view AS
    SELECT
      pe.id,
      pe.slug,
      pe.title,
      pe.title_translations,
      pe.starts_at,
      pe.ends_at,
      pe.venue_id,
      pe.category_id,
      pe.min_price,
      pe.max_price,
      pe.currency,
      pe.ticket_url,
      pe.inserted_at,
      pe.updated_at,

      -- Best source information (highest priority, most recent)
      pes.id as source_id,
      pes.description_translations,
      pes.image_url,
      pes.source_url,
      pes.external_id,
      pes.metadata as source_metadata,
      pes.last_seen_at as source_last_seen_at,

      -- Venue information
      v.name as venue_name,
      v.slug as venue_slug,
      v.address as venue_address,
      v.latitude as venue_latitude,
      v.longitude as venue_longitude,
      v.venue_type,

      -- City information
      c.id as city_id,
      c.name as city_name,
      c.slug as city_slug,

      -- Country information
      co.id as country_id,
      co.name as country_name,
      co.code as country_code,

      -- Category information
      cat.name as category_name,
      cat.slug as category_slug,
      cat.translations as category_translations,
      cat.icon as category_icon,
      cat.color as category_color

    FROM public_events pe
    LEFT JOIN LATERAL (
      SELECT * FROM public_event_sources
      WHERE event_id = pe.id
      ORDER BY
        COALESCE(
          CASE
            WHEN (metadata->>'priority') ~ '^[0-9]+$' THEN (metadata->>'priority')::integer
            ELSE NULL
          END,
          10
        ) ASC,
        last_seen_at DESC
      LIMIT 1
    ) pes ON true
    LEFT JOIN venues v ON pe.venue_id = v.id
    LEFT JOIN cities c ON v.city_id = c.id
    LEFT JOIN countries co ON c.country_id = co.id
    LEFT JOIN categories cat ON pe.category_id = cat.id;
    """

    # Create indexes for performance on base tables
    create_if_not_exists index(:public_events, [:slug])  # Critical for show page lookups
    create_if_not_exists index(:public_events, [:starts_at])
    create_if_not_exists index(:public_events, [:venue_id])
    create_if_not_exists index(:public_events, [:category_id])
    create_if_not_exists index(:public_events, [:min_price])
    create_if_not_exists index(:public_events, [:max_price])
    create_if_not_exists index(:public_event_sources, [:event_id, :last_seen_at])
  end

  def down do
    execute "DROP VIEW IF EXISTS public_events_view"

    # Note: We keep the indexes as they are beneficial regardless
  end
end