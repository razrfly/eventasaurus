defmodule EventasaurusApp.Repo.Migrations.ChangePublicEventsVenueFkToRestrict do
  use Ecto.Migration

  @moduledoc """
  Fixes public events losing venue_id via ON DELETE SET NULL.

  The original FK `public_events_venue_id_fkey` used `ON DELETE SET NULL`.
  When venues were deleted (DB reset, cleanup, deduplication race), PostgreSQL
  silently nullified `venue_id` on all referencing events — bypassing Ecto
  changeset validation.

  Three changes:
  1. Clean orphaned events (scraped events that lost their venue)
  2. Change FK from SET NULL to RESTRICT
  3. Add defense-in-depth trigger preventing venue_id nullification on public events

  See GitHub issue #3670 for full context.
  """

  def up do
    # 1. Delete orphaned public events (scraped events that lost their venue).
    #    These will be recreated correctly by the next scraper run.
    execute """
    DELETE FROM public_events
    WHERE venue_id IS NULL
      AND id IN (SELECT DISTINCT event_id FROM public_event_sources)
    """

    # 2. Change FK from SET NULL to RESTRICT.
    #    Drop the old FK and add new one — prevents venue deletion when events reference it.
    execute "ALTER TABLE public_events DROP CONSTRAINT public_events_venue_id_fkey"

    execute """
    ALTER TABLE public_events
    ADD CONSTRAINT public_events_venue_id_fkey
    FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE RESTRICT
    """

    # 3. Defense-in-depth trigger: prevent venue_id from being set to NULL
    #    on events that have source records (public/scraped events).
    #    Fires on UPDATE only — INSERT is guarded by Ecto changeset validation.
    #    The WHEN clause ensures zero overhead on normal updates.
    execute """
    CREATE OR REPLACE FUNCTION prevent_public_event_venue_null()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.venue_id IS NULL AND EXISTS (
        SELECT 1 FROM public_event_sources WHERE event_id = NEW.id
      ) THEN
        RAISE EXCEPTION 'Public events (with sources) must have a venue_id. Event ID: %', NEW.id
          USING HINT = 'Scraped/public events require a venue. Only private events can have NULL venue_id.';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER enforce_venue_on_public_events
      BEFORE UPDATE ON public_events
      FOR EACH ROW
      WHEN (NEW.venue_id IS NULL)
      EXECUTE FUNCTION prevent_public_event_venue_null();
    """

    # 4. Guard on public_event_sources: prevent linking a source to an event
    #    whose venue_id is NULL. This closes the gap where a new source record
    #    could reference an event that has no venue.
    execute """
    CREATE OR REPLACE FUNCTION prevent_public_event_source_link_to_event_without_venue()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM public_events WHERE id = NEW.event_id AND venue_id IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'Cannot link source to public_event without a venue. Event ID: %', NEW.event_id
          USING HINT = 'The referenced public_event must have a non-NULL venue_id before adding sources.';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER enforce_venue_on_public_event_sources
      BEFORE INSERT OR UPDATE ON public_event_sources
      FOR EACH ROW
      EXECUTE FUNCTION prevent_public_event_source_link_to_event_without_venue();
    """
  end

  def down do
    # Drop triggers and functions
    execute "DROP TRIGGER IF EXISTS enforce_venue_on_public_event_sources ON public_event_sources"
    execute "DROP FUNCTION IF EXISTS prevent_public_event_source_link_to_event_without_venue()"
    execute "DROP TRIGGER IF EXISTS enforce_venue_on_public_events ON public_events"
    execute "DROP FUNCTION IF EXISTS prevent_public_event_venue_null()"

    # Revert FK back to SET NULL
    execute "ALTER TABLE public_events DROP CONSTRAINT public_events_venue_id_fkey"

    execute """
    ALTER TABLE public_events
    ADD CONSTRAINT public_events_venue_id_fkey
    FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE SET NULL
    """
  end
end
