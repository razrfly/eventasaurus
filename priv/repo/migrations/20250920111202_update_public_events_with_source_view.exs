defmodule EventasaurusApp.Repo.Migrations.UpdatePublicEventsWithSourceView do
  use Ecto.Migration

  def up do
    # Drop the view that depends on description column
    execute "DROP VIEW IF EXISTS public_events_with_source CASCADE"

    # Recreate the view without description column and with description_translations from sources
    execute """
    CREATE OR REPLACE VIEW public_events_with_source AS
    SELECT
      pe.id,
      pe.title,
      pe.title_translations,
      pe.slug,
      pe.starts_at,
      pe.ends_at,
      pe.ticket_url,
      pe.min_price,
      pe.max_price,
      pe.currency,
      pe.venue_id,
      pe.category_id,
      pe.inserted_at,
      pe.updated_at,
      pes.external_id,
      pes.source_url,
      pes.description_translations,
      pes.metadata as source_metadata,
      pes.source_id,
      pes.last_seen_at as source_last_seen_at
    FROM public_events pe
    LEFT JOIN LATERAL (
      -- Get the primary source (highest priority, or most recent if no priority)
      SELECT *
      FROM public_event_sources
      WHERE event_id = pe.id
      ORDER BY
        COALESCE((metadata->>'priority')::integer, 10) ASC,
        last_seen_at DESC
      LIMIT 1
    ) pes ON true;
    """
  end

  def down do
    # Drop the updated view
    execute "DROP VIEW IF EXISTS public_events_with_source CASCADE"

    # Restore the previous view definition (from migration 20250920094257)
    execute """
    CREATE OR REPLACE VIEW public_events_with_source AS
    SELECT
      pe.id,
      pe.title,
      pe.slug,
      pe.description,
      pe.starts_at,
      pe.ends_at,
      pe.ticket_url,
      pe.min_price,
      pe.max_price,
      pe.currency,
      pe.venue_id,
      pe.category_id,
      pe.inserted_at,
      pe.updated_at,
      pes.external_id,
      pes.source_url,
      pes.metadata as source_metadata,
      pes.source_id,
      pes.last_seen_at as source_last_seen_at
    FROM public_events pe
    LEFT JOIN LATERAL (
      -- Get the primary source (highest priority, or most recent if no priority)
      SELECT *
      FROM public_event_sources
      WHERE event_id = pe.id
      ORDER BY
        COALESCE((metadata->>'priority')::integer, 10) ASC,
        last_seen_at DESC
      LIMIT 1
    ) pes ON true;
    """
  end
end
