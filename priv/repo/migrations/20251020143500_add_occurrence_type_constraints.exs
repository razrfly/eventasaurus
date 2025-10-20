defmodule EventasaurusApp.Repo.Migrations.AddOccurrenceTypeConstraints do
  use Ecto.Migration

  @moduledoc """
  Adds CHECK constraints to enforce valid occurrence type values.

  Phase 3 of issue #1875: Add database-level validation for occurrence types.

  This migration adds CHECK constraints to:
  1. public_events.occurrences->>'type' - Must be one of: explicit, pattern, exhibition, recurring
  2. public_event_sources.metadata->>'occurrence_type' - Must be one of: explicit, pattern, exhibition, recurring

  These constraints work alongside the OccurrenceValidator module to prevent
  invalid occurrence type values from being stored in the database.
  """

  def up do
    # Add CHECK constraint on public_events.occurrences->>'type'
    # This ensures the occurrence type in the occurrences JSONB field is valid
    execute """
    ALTER TABLE public_events
    ADD CONSTRAINT valid_occurrence_type
    CHECK (
      occurrences IS NULL OR
      (occurrences->>'type') IN ('explicit', 'pattern', 'exhibition', 'recurring')
    )
    """

    # Add CHECK constraint on public_event_sources.metadata->>'occurrence_type'
    # This ensures the occurrence_type stored in metadata JSONB field is valid
    execute """
    ALTER TABLE public_event_sources
    ADD CONSTRAINT valid_metadata_occurrence_type
    CHECK (
      metadata IS NULL OR
      (metadata->>'occurrence_type') IS NULL OR
      (metadata->>'occurrence_type') IN ('explicit', 'pattern', 'exhibition', 'recurring')
    )
    """
  end

  def down do
    # Remove CHECK constraint from public_events
    execute "ALTER TABLE public_events DROP CONSTRAINT IF EXISTS valid_occurrence_type"

    # Remove CHECK constraint from public_event_sources
    execute "ALTER TABLE public_event_sources DROP CONSTRAINT IF EXISTS valid_metadata_occurrence_type"
  end
end
