defmodule EventasaurusApp.Repo.Migrations.CleanupLegacyOccurrenceTypes do
  use Ecto.Migration

  @moduledoc """
  Cleans up legacy occurrence type values before adding CHECK constraints.

  Phase 3 of issue #1875: Clean up existing data before adding constraints.

  This migration normalizes legacy occurrence type values:
  - "one_time" → "explicit"
  - "unknown" → "exhibition"
  - "movie" → "explicit" (if any exist)

  This must run BEFORE the add_occurrence_type_constraints migration.
  """

  def up do
    # Update public_event_sources.metadata: "one_time" → "explicit"
    execute """
    UPDATE public_event_sources
    SET metadata = jsonb_set(metadata, '{occurrence_type}', '"explicit"')
    WHERE metadata->>'occurrence_type' = 'one_time'
    """

    # Update public_event_sources.metadata: "unknown" → "exhibition"
    execute """
    UPDATE public_event_sources
    SET metadata = jsonb_set(metadata, '{occurrence_type}', '"exhibition"')
    WHERE metadata->>'occurrence_type' = 'unknown'
    """

    # Update public_event_sources.metadata: "movie" → "explicit" (if any)
    execute """
    UPDATE public_event_sources
    SET metadata = jsonb_set(metadata, '{occurrence_type}', '"explicit"')
    WHERE metadata->>'occurrence_type' = 'movie'
    """

    # Note: We don't need to update public_events.occurrences here because
    # the event_processor already creates them with valid types.
    # Any invalid values in occurrences would be from manual data entry or old code.
  end

  def down do
    # We don't reverse this migration because:
    # 1. We can't reliably determine which records were changed
    # 2. We don't want to restore invalid data
    # 3. The new values are semantically equivalent
    :ok
  end
end
