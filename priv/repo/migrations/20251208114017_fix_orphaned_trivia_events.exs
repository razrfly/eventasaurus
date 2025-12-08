defmodule EventasaurusApp.Repo.Migrations.FixOrphanedTriviaEvents do
  use Ecto.Migration

  @moduledoc """
  Fixes orphaned public_events that have no corresponding public_event_sources record.

  These orphans were created during Oct 26-31, 2025 due to a bug that has since been fixed
  (atomic transactions via Ecto.Multi now ensure event + source are created together).

  This migration re-links orphaned events to their sources based on slug patterns:
  - quiz-night-at-% → Quizmeisters (source_id: 9)
  - speedquizzing-% → Speed Quizzing (source_id: 11)
  - inquizition-% → Inquizition (source_id: 10)

  See GitHub issue #2569 for full analysis.
  """

  def up do
    # Fix Quizmeisters orphans (39 events with slug pattern 'quiz-night-at-%')
    execute("""
    INSERT INTO public_event_sources (event_id, source_id, last_seen_at, inserted_at, updated_at)
    SELECT pe.id, 9, NOW(), NOW(), NOW()
    FROM public_events pe
    LEFT JOIN public_event_sources pes ON pes.event_id = pe.id
    WHERE pes.id IS NULL
      AND pe.slug LIKE 'quiz-night-at-%'
    """)

    # Fix Speed Quizzing orphans (18 events with slug pattern 'speedquizzing-%')
    execute("""
    INSERT INTO public_event_sources (event_id, source_id, last_seen_at, inserted_at, updated_at)
    SELECT pe.id, 11, NOW(), NOW(), NOW()
    FROM public_events pe
    LEFT JOIN public_event_sources pes ON pes.event_id = pe.id
    WHERE pes.id IS NULL
      AND pe.slug LIKE 'speedquizzing-%'
    """)

    # Fix Inquizition orphans (1 event with slug pattern 'inquizition-%')
    execute("""
    INSERT INTO public_event_sources (event_id, source_id, last_seen_at, inserted_at, updated_at)
    SELECT pe.id, 10, NOW(), NOW(), NOW()
    FROM public_events pe
    LEFT JOIN public_event_sources pes ON pes.event_id = pe.id
    WHERE pes.id IS NULL
      AND pe.slug LIKE 'inquizition-%'
    """)
  end

  def down do
    # Remove the source links we created (based on the same slug patterns)
    # Note: This only removes links created by this migration, not legitimate ones

    execute("""
    DELETE FROM public_event_sources
    WHERE id IN (
      SELECT pes.id
      FROM public_event_sources pes
      JOIN public_events pe ON pe.id = pes.event_id
      WHERE pe.slug LIKE 'quiz-night-at-%'
        AND pes.source_id = 9
    )
    """)

    execute("""
    DELETE FROM public_event_sources
    WHERE id IN (
      SELECT pes.id
      FROM public_event_sources pes
      JOIN public_events pe ON pe.id = pes.event_id
      WHERE pe.slug LIKE 'speedquizzing-%'
        AND pes.source_id = 11
    )
    """)

    execute("""
    DELETE FROM public_event_sources
    WHERE id IN (
      SELECT pes.id
      FROM public_event_sources pes
      JOIN public_events pe ON pe.id = pes.event_id
      WHERE pe.slug LIKE 'inquizition-%'
        AND pes.source_id = 10
    )
    """)
  end
end
