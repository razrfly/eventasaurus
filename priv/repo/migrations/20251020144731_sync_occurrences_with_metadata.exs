defmodule EventasaurusApp.Repo.Migrations.SyncOccurrencesWithMetadata do
  use Ecto.Migration

  @moduledoc """
  Syncs public_events.occurrences->>'type' with public_event_sources.metadata->>'occurrence_type'.

  Optional data migration for issue #1874: Fixes stats distribution showing 100% explicit
  when should show ~96% exhibition, 2% recurring, etc.

  This migration:
  1. Updates 335 exhibition events from "explicit" to "exhibition"
  2. Updates 7 recurring events from "explicit" to "recurring"

  Safe to run because:
  - CHECK constraints prevent invalid values
  - OccurrenceValidator ensures only valid types exist
  - Metadata values already normalized in previous migration
  """

  def up do
    # Update occurrences.type to match metadata.occurrence_type
    # This only affects events where metadata has a different type than occurrences
    # Uses CTE to ensure deterministic, null-safe, and idempotent updates
    execute """
    WITH src AS (
      SELECT
        pes.event_id,
        MIN(pes.metadata->>'occurrence_type') AS occurrence_type
      FROM public_event_sources pes
      WHERE pes.metadata->>'occurrence_type' IS NOT NULL
      GROUP BY pes.event_id
      HAVING COUNT(DISTINCT pes.metadata->>'occurrence_type') = 1
    )
    UPDATE public_events AS pe
    SET occurrences = jsonb_set(
      COALESCE(pe.occurrences, '{}'::jsonb),
      '{type}',
      to_jsonb(src.occurrence_type)
    )
    FROM src
    WHERE pe.id = src.event_id
      AND (pe.occurrences->>'type') IS DISTINCT FROM src.occurrence_type;
    """
  end

  def down do
    # Revert all exhibition and recurring back to explicit
    # This is safe but loses the correct classification
    execute """
    UPDATE public_events
    SET occurrences = jsonb_set(
      occurrences,
      '{type}',
      '"explicit"'
    )
    WHERE occurrences->>'type' IN ('exhibition', 'recurring');
    """
  end
end
