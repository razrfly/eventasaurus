defmodule EventasaurusApp.Repo.Migrations.RemoveExternalIdMetadataFromPublicEvents do
  use Ecto.Migration

  def up do
    # First, ensure all data is properly migrated to public_event_sources
    execute """
    INSERT INTO public_event_sources (event_id, source_id, external_id, metadata, last_seen_at, inserted_at, updated_at)
    SELECT DISTINCT ON (pe.id)
      pe.id as event_id,
      COALESCE(pes.source_id, 1) as source_id,  -- Default to source_id 1 if not already linked
      pe.external_id,
      pe.metadata,
      NOW() as last_seen_at,
      NOW() as inserted_at,
      NOW() as updated_at
    FROM public_events pe
    LEFT JOIN public_event_sources pes ON pes.event_id = pe.id
    WHERE pe.external_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public_event_sources pes2
        WHERE pes2.event_id = pe.id
          AND pes2.external_id = pe.external_id
      )
    ON CONFLICT (event_id, source_id) DO UPDATE
    SET
      external_id = EXCLUDED.external_id,
      metadata = EXCLUDED.metadata,
      last_seen_at = EXCLUDED.last_seen_at,
      updated_at = EXCLUDED.updated_at;
    """

    # Drop all views that depend on these columns
    execute "DROP VIEW IF EXISTS public_events_with_source CASCADE;"
    execute "DROP VIEW IF EXISTS public_events_with_category CASCADE;"

    # Now remove the columns from public_events
    alter table(:public_events) do
      remove :external_id
      remove :metadata
    end

    # Recreate the view without referencing pe.external_id or pe.metadata
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

  def down do
    # Drop the view
    execute "DROP VIEW IF EXISTS public_events_with_source;"

    # Re-add the columns
    alter table(:public_events) do
      add :external_id, :string
      add :metadata, :map, default: %{}
    end

    # Restore data from public_event_sources (using primary source)
    execute """
    UPDATE public_events pe
    SET
      external_id = pes.external_id,
      metadata = pes.metadata
    FROM (
      SELECT DISTINCT ON (event_id)
        event_id,
        external_id,
        metadata
      FROM public_event_sources
      ORDER BY
        event_id,
        COALESCE((metadata->>'priority')::integer, 10) ASC,
        last_seen_at DESC
    ) pes
    WHERE pe.id = pes.event_id;
    """

    # Recreate the original view
    execute """
    CREATE OR REPLACE VIEW public_events_with_source AS
    SELECT
      pe.*,
      pes.external_id as source_external_id,
      pes.source_url,
      pes.metadata as source_metadata,
      pes.source_id,
      pes.last_seen_at as source_last_seen_at
    FROM public_events pe
    LEFT JOIN LATERAL (
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