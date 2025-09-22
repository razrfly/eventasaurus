defmodule EventasaurusApp.Repo.Migrations.CleanupSingleEventOccurrences do
  use Ecto.Migration

  def up do
    # Clean up single events that incorrectly have occurrences with exactly 1 date
    # These are false positives from the bug where ALL events were initialized with occurrences
    execute """
    UPDATE public_events
    SET occurrences = NULL
    WHERE occurrences IS NOT NULL
    AND (
      -- Single occurrence (count = 1)
      jsonb_array_length(occurrences->'dates') = 1
      -- Or empty dates array
      OR jsonb_array_length(occurrences->'dates') = 0
      -- Or missing dates key
      OR occurrences->'dates' IS NULL
    )
    """

    # Also clean up any events where the occurrence structure exists but is essentially empty
    execute """
    UPDATE public_events
    SET occurrences = NULL
    WHERE occurrences = '{}'::jsonb
    OR occurrences = '{"dates": []}'::jsonb
    OR occurrences = '{"dates": null}'::jsonb
    """
  end

  def down do
    # This migration is not reversible as we're removing incorrect data
    # The original bug would need to be re-run to recreate the false positives
    :ok
  end
end
