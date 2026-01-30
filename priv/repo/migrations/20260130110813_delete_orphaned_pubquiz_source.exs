defmodule EventasaurusApp.Repo.Migrations.DeleteOrphanedPubquizSource do
  use Ecto.Migration

  @moduledoc """
  Delete orphaned 'pubquiz' source record and merge its events.

  The pubquiz source had an internal inconsistency:
  - Source.key() returned "pubquiz-pl"
  - Config.source_config().slug returned "pubquiz"

  This caused two source records with different IDs in different environments.

  Migration steps:
  1. Delete duplicate public_events that only have pubquiz source AND
     their external_id already exists in pubquiz-pl (keep the pubquiz-pl version)
  2. Delete pubquiz event_sources where external_id exists in pubquiz-pl
  3. Reassign remaining pubquiz event_sources to pubquiz-pl
  4. Delete the orphaned 'pubquiz' source record

  Note: Uses slug-based lookups to work correctly regardless of source IDs.
  """

  def up do
    # Step 1: Delete duplicate PUBLIC_EVENTS that only have pubquiz source
    # AND their external_id already exists in pubquiz-pl
    # (these are true duplicates - keep the pubquiz-pl version)
    execute """
    DELETE FROM public_events pe
    WHERE pe.id IN (
      SELECT pes.event_id
      FROM public_event_sources pes
      JOIN sources s ON s.id = pes.source_id
      WHERE s.slug = 'pubquiz'
        AND NOT EXISTS (
          SELECT 1 FROM public_event_sources pes2
          JOIN sources s2 ON s2.id = pes2.source_id
          WHERE pes2.event_id = pes.event_id AND s2.slug != 'pubquiz'
        )
        AND pes.external_id IN (
          SELECT pes3.external_id FROM public_event_sources pes3
          JOIN sources s3 ON s3.id = pes3.source_id
          WHERE s3.slug = 'pubquiz-pl'
        )
    );
    """

    # Step 2: Delete pubquiz event_sources where external_id exists in pubquiz-pl
    execute """
    DELETE FROM public_event_sources pes
    USING sources s
    WHERE pes.source_id = s.id
      AND s.slug = 'pubquiz'
      AND pes.external_id IN (
        SELECT pes2.external_id FROM public_event_sources pes2
        JOIN sources s2 ON s2.id = pes2.source_id
        WHERE s2.slug = 'pubquiz-pl'
      );
    """

    # Step 3: Reassign remaining pubquiz event_sources to pubquiz-pl
    execute """
    UPDATE public_event_sources pes
    SET source_id = (SELECT id FROM sources WHERE slug = 'pubquiz-pl')
    FROM sources s
    WHERE pes.source_id = s.id AND s.slug = 'pubquiz';
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
