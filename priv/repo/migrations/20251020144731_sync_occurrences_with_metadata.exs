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
    execute """
    UPDATE public_events pe
    SET occurrences = jsonb_set(
      pe.occurrences,
      '{type}',
      to_jsonb(pes.metadata->>'occurrence_type')
    )
    FROM public_event_sources pes
    WHERE pe.id = pes.event_id
      AND pes.metadata->>'occurrence_type' IS NOT NULL
      AND pe.occurrences->>'type' != pes.metadata->>'occurrence_type';
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
