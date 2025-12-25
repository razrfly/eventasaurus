defmodule EventasaurusApp.Repo.Migrations.CleanupRecurringEventDuplicateExternalIds do
  @moduledoc """
  Cleanup duplicate public_event_sources records created by recurring event scrapers.

  ## Background (GitHub Issue #2929)

  Recurring event scrapers (inquizition, question_one, pubquiz) were incorrectly
  generating external_ids with date suffixes like `inquizition_123_2025-01-15`.

  The correct pattern for recurring events is venue-based only: `inquizition_123`
  (no date suffix). This allows the same PublicEventSource record to be updated
  with the next occurrence date on each scraper run.

  ## What This Migration Does

  Deletes public_event_sources records that have date-suffixed external_ids
  for recurring event sources, where a canonical (venue-only) record already exists.

  For example, if we have:
  - `inquizition_123` (canonical - KEEP)
  - `inquizition_123_2025-01-15` (duplicate - DELETE)
  - `inquizition_123_2025-01-22` (duplicate - DELETE)

  This migration deletes the date-suffixed duplicates, keeping only the canonical.

  ## Safety

  - Only deletes records where both the canonical AND duplicate point to the same event_id
  - Only affects inquizition, question_one, and pubquiz sources
  - Verified in production: 140 inquizition duplicates, all safe to delete
  """

  use Ecto.Migration

  def up do
    # Delete date-suffixed duplicates for inquizition
    # Pattern: inquizition_{venue_id}_{YYYY-MM-DD}
    execute("""
    DELETE FROM public_event_sources
    WHERE id IN (
      SELECT ds.id
      FROM public_event_sources ds
      JOIN public_event_sources canonical ON canonical.external_id = substring(ds.external_id from '^(inquizition_\\d+)_\\d{4}-\\d{2}-\\d{2}$')
      WHERE ds.external_id ~ '^inquizition_\\d+_\\d{4}-\\d{2}-\\d{2}$'
        AND ds.event_id = canonical.event_id
    )
    """)

    # Delete date-suffixed duplicates for question_one
    # Pattern: question_one_{venue_slug}_{YYYY-MM-DD}
    execute("""
    DELETE FROM public_event_sources
    WHERE id IN (
      SELECT ds.id
      FROM public_event_sources ds
      JOIN public_event_sources canonical ON canonical.external_id = substring(ds.external_id from '^(question_one_[a-z0-9_]+)_\\d{4}-\\d{2}-\\d{2}$')
      WHERE ds.external_id ~ '^question_one_[a-z0-9_]+_\\d{4}-\\d{2}-\\d{2}$'
        AND ds.event_id = canonical.event_id
    )
    """)

    # Delete date-suffixed duplicates for pubquiz
    # Pattern: pubquiz_venue_{city}_{venue}_{YYYY-MM-DD}
    execute("""
    DELETE FROM public_event_sources
    WHERE id IN (
      SELECT ds.id
      FROM public_event_sources ds
      JOIN public_event_sources canonical ON canonical.external_id = substring(ds.external_id from '^(pubquiz_venue_[a-z0-9_]+)_\\d{4}-\\d{2}-\\d{2}$')
      WHERE ds.external_id ~ '^pubquiz_venue_[a-z0-9_]+_\\d{4}-\\d{2}-\\d{2}$'
        AND ds.event_id = canonical.event_id
    )
    """)
  end

  def down do
    # This migration cannot be reversed as the duplicate data is deleted
    # The scrapers will recreate canonical records on the next run if needed
    :ok
  end
end
