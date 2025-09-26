defmodule EventasaurusApp.Repo.Migrations.RemoveUnusedFieldsFromPublicEvents do
  use Ecto.Migration

  def up do
    # Drop the view first since it depends on the columns we're removing
    execute("DROP VIEW IF EXISTS public_events_view")

    # Drop unused indexes first
    drop_if_exists index(:public_events, [:min_price])
    drop_if_exists index(:public_events, [:max_price])
    drop_if_exists index(:public_events, [:min_price, :max_price])

    # Remove unused fields from public_events table
    # These fields were moved to public_event_sources where they belong
    alter table(:public_events) do
      remove :min_price, :decimal, null: true
      remove :max_price, :decimal, null: true
      remove :currency, :string, null: true
      remove :ticket_url, :string, null: true
    end

    # Recreate the view without the removed fields
    execute("""
    CREATE VIEW public_events_view AS
    SELECT pe.id,
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
       pes.source_url AS ticket_url,
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
        LEFT JOIN LATERAL ( SELECT public_event_sources.id,
               public_event_sources.event_id,
               public_event_sources.source_id,
               public_event_sources.source_url,
               public_event_sources.external_id,
               public_event_sources.last_seen_at,
               public_event_sources.metadata,
               public_event_sources.inserted_at,
               public_event_sources.updated_at,
               public_event_sources.description_translations,
               public_event_sources.image_url,
               public_event_sources.min_price,
               public_event_sources.max_price,
               public_event_sources.currency,
               public_event_sources.is_free
              FROM public_event_sources
             WHERE public_event_sources.event_id = pe.id
             ORDER BY (COALESCE(
                   CASE
                       WHEN (public_event_sources.metadata ->> 'priority'::text) ~ '^[0-9]+$'::text THEN (public_event_sources.metadata ->> 'priority'::text)::integer
                       ELSE NULL::integer
                   END, 10)), public_event_sources.last_seen_at DESC
            LIMIT 1) pes ON true
        LEFT JOIN venues v ON pe.venue_id = v.id
        LEFT JOIN cities c ON v.city_id = c.id
        LEFT JOIN countries co ON c.country_id = co.id
        LEFT JOIN categories cat ON pe.category_id = cat.id;
    """)
  end

  def down do
    # Re-add the fields
    alter table(:public_events) do
      add :min_price, :decimal, null: true
      add :max_price, :decimal, null: true
      add :currency, :string, null: true
      add :ticket_url, :string, null: true
    end

    # Re-create the indexes
    create index(:public_events, [:min_price])
    create index(:public_events, [:max_price])
    create index(:public_events, [:min_price, :max_price])
  end
end