defmodule EventasaurusApp.Repo.Migrations.AddPublicEventsWithSourceView do
  use Ecto.Migration

  def up do
    # Create a view that joins public_events with their primary event_source
    # This provides backward compatibility for code that needs external_id
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

    # Create an index to optimize the view's lateral join
    create_if_not_exists index(:public_event_sources, [:event_id])

    # Add a partial index for finding events by external_id efficiently
    create_if_not_exists index(:public_event_sources, [:external_id, :source_id],
      unique: true,
      name: :public_event_sources_external_id_source_id_index)
  end

  def down do
    drop_if_exists index(:public_event_sources, [:external_id, :source_id],
      name: :public_event_sources_external_id_source_id_index)

    drop_if_exists index(:public_event_sources, [:event_id])

    execute "DROP VIEW IF EXISTS public_events_with_source;"
  end
end