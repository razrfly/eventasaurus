defmodule EventasaurusApp.Repo.Migrations.DeleteRemainingOrphanedEvents do
  use Ecto.Migration

  @moduledoc """
  Deletes the 8 remaining orphaned public_events that have no source linkage.

  These events are miscellaneous orphans from various sources (Cinema City,
  BandsInTown, Karnet, Resident Advisor, Waw4Free) that were created during
  Oct-Nov 2025 due to a bug that has since been fixed.

  The previous migration (20251208114017) fixed 58 trivia orphans by linking
  them to their sources. These 8 remaining events don't follow identifiable
  patterns and are old/low-value, so we delete them instead.

  See GitHub issue #2569 for full analysis.
  """

  def up do
    # Delete related performers for remaining orphans (1 record)
    execute("""
    DELETE FROM public_event_performers
    WHERE event_id IN (
      SELECT pe.id
      FROM public_events pe
      LEFT JOIN public_event_sources pes ON pes.event_id = pe.id
      WHERE pes.id IS NULL
    )
    """)

    # Delete related categories for remaining orphans (11 records)
    execute("""
    DELETE FROM public_event_categories
    WHERE event_id IN (
      SELECT pe.id
      FROM public_events pe
      LEFT JOIN public_event_sources pes ON pes.event_id = pe.id
      WHERE pes.id IS NULL
    )
    """)

    # Delete the orphaned events themselves (8 events)
    execute("""
    DELETE FROM public_events
    WHERE id IN (
      SELECT pe.id
      FROM public_events pe
      LEFT JOIN public_event_sources pes ON pes.event_id = pe.id
      WHERE pes.id IS NULL
    )
    """)
  end

  def down do
    # Deleted events cannot be restored - this is intentional.
    # They were orphaned data with no source attribution and low value.
    :ok
  end
end
