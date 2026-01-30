defmodule EventasaurusApp.Repo.Migrations.DeleteOrphanedPubquizSource do
  use Ecto.Migration

  @moduledoc """
  Delete orphaned 'pubquiz' source record and merge its events.

  The pubquiz source had an internal inconsistency:
  - Source.key() returned "pubquiz-pl"
  - Config.source_config().slug returned "pubquiz"

  This caused two source records (id=4 'pubquiz', id=16 'pubquiz-pl').

  Data state:
  - 107 event_sources linked to pubquiz (id=4)
  - 87 of these have external_id that also exists in pubquiz-pl (id=16)
  - Some events ONLY have pubquiz source (no other sources)
  - 5 of those "pubquiz-only" events have duplicate external_ids in pubquiz-pl

  Migration steps:
  1. Delete duplicate public_events that only have pubquiz source AND
     their external_id already exists in pubquiz-pl (keep the pubquiz-pl version)
  2. Delete pubquiz event_sources where external_id exists in pubquiz-pl
  3. Reassign remaining pubquiz event_sources to pubquiz-pl
  4. Delete the orphaned 'pubquiz' source record
  """

  def up do
    pubquiz_id = 4
    pubquiz_pl_id = 16

    # Step 1: Delete duplicate PUBLIC_EVENTS that only have pubquiz source
    # AND their external_id already exists in pubquiz-pl
    # (these are true duplicates - keep the pubquiz-pl version)
    execute """
    DELETE FROM public_events pe
    WHERE pe.id IN (
      SELECT pes.event_id
      FROM public_event_sources pes
      WHERE pes.source_id = #{pubquiz_id}
        AND NOT EXISTS (
          SELECT 1 FROM public_event_sources pes2
          WHERE pes2.event_id = pes.event_id AND pes2.source_id != #{pubquiz_id}
        )
        AND pes.external_id IN (
          SELECT external_id FROM public_event_sources WHERE source_id = #{pubquiz_pl_id}
        )
    );
    """

    # Step 2: Delete pubquiz event_sources where external_id exists in pubquiz-pl
    execute """
    DELETE FROM public_event_sources pes
    WHERE pes.source_id = #{pubquiz_id}
      AND pes.external_id IN (
        SELECT external_id FROM public_event_sources
        WHERE source_id = #{pubquiz_pl_id}
      );
    """

    # Step 3: Reassign remaining pubquiz event_sources to pubquiz-pl
    execute """
    UPDATE public_event_sources
    SET source_id = #{pubquiz_pl_id}
    WHERE source_id = #{pubquiz_id};
    """

    # Step 4: Delete the orphaned "pubquiz" source
    execute """
    DELETE FROM sources WHERE slug = 'pubquiz';
    """
  end

  def down do
    execute """
    INSERT INTO sources (slug, name, is_active, priority, inserted_at, updated_at)
    VALUES ('pubquiz', 'PubQuiz.pl', true, 50, NOW(), NOW())
    ON CONFLICT (slug) DO NOTHING;
    """
  end
end
