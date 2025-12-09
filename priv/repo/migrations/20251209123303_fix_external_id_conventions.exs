defmodule EventasaurusApp.Repo.Migrations.FixExternalIdConventions do
  use Ecto.Migration

  @moduledoc """
  Fixes external_id format inconsistencies for Speed Quizzing and Karnet sources.

  ## Speed Quizzing
  - OLD: `speed-quizzing-{id}` (uses hyphens)
  - NEW: `speed_quizzing_{id}` (uses underscores for consistency)

  ## Karnet
  - OLD: `karnet_event_{id}` (redundant `_event_` type component)
  - NEW: `karnet_{id}` (follows standard pattern)

  See: docs/EXTERNAL_ID_CONVENTIONS.md
  Related: GitHub issue #2602
  """

  def up do
    # Speed Quizzing: hyphens → underscores
    # First, delete old format records where new format already exists (from updated scraper code)
    execute("""
    DELETE FROM public_event_sources old_record
    WHERE old_record.external_id LIKE 'speed-quizzing-%'
      AND EXISTS (
        SELECT 1 FROM public_event_sources new_record
        WHERE new_record.source_id = old_record.source_id
          AND new_record.external_id = REPLACE(old_record.external_id, 'speed-quizzing-', 'speed_quizzing_')
      )
    """)

    # Then rename remaining old format records
    execute("""
    UPDATE public_event_sources
    SET external_id = REPLACE(external_id, 'speed-quizzing-', 'speed_quizzing_')
    WHERE external_id LIKE 'speed-quizzing-%'
    """)

    # Karnet: remove redundant _event_ type component
    # First, delete old format records where new format already exists (from updated scraper code)
    execute("""
    DELETE FROM public_event_sources old_record
    WHERE old_record.external_id LIKE 'karnet_event_%'
      AND EXISTS (
        SELECT 1 FROM public_event_sources new_record
        WHERE new_record.source_id = old_record.source_id
          AND new_record.external_id = REPLACE(old_record.external_id, 'karnet_event_', 'karnet_')
      )
    """)

    # Then rename remaining old format records
    execute("""
    UPDATE public_event_sources
    SET external_id = REPLACE(external_id, 'karnet_event_', 'karnet_')
    WHERE external_id LIKE 'karnet_event_%'
    """)
  end

  def down do
    # Reverse Speed Quizzing changes
    execute("""
    UPDATE public_event_sources
    SET external_id = REPLACE(external_id, 'speed_quizzing_', 'speed-quizzing-')
    WHERE external_id LIKE 'speed_quizzing_%'
    """)

    # Reverse Karnet changes
    # Note: This adds _event_ back to all karnet_ entries that don't already have it
    execute("""
    UPDATE public_event_sources
    SET external_id = REPLACE(external_id, 'karnet_', 'karnet_event_')
    WHERE external_id LIKE 'karnet_%'
      AND external_id NOT LIKE 'karnet_event_%'
    """)
  end
end
