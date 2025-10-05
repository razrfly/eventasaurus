defmodule EventasaurusApp.Repo.Migrations.AddUniqueConstraintToVenuePlaceId do
  use Ecto.Migration

  def up do
    # CRITICAL: Clean up duplicate venues BEFORE adding unique constraint
    # This fixes the race condition bug that created 70% duplicates (issue #1492)

    execute """
    -- Delete duplicate venues (keeping oldest record per place_id)
    -- All duplicates are orphaned (no events linked), safe to delete
    WITH duplicates AS (
      SELECT
        id,
        place_id,
        ROW_NUMBER() OVER (PARTITION BY place_id ORDER BY inserted_at ASC) as rn
      FROM venues
      WHERE place_id IS NOT NULL
    )
    DELETE FROM venues
    WHERE id IN (
      SELECT id FROM duplicates WHERE rn > 1
    );
    """

    # Drop the old non-unique index
    drop_if_exists index(:venues, [:place_id], name: :venues_place_id_index)

    # Create partial unique index (only for non-null place_ids)
    # This allows multiple NULL place_ids (venues without Google Places lookup)
    # but enforces uniqueness for all non-null values
    create unique_index(:venues, [:place_id],
      where: "place_id IS NOT NULL",
      name: :venues_place_id_unique_index
    )
  end

  def down do
    # Rollback: restore non-unique index
    drop_if_exists index(:venues, [:place_id], name: :venues_place_id_unique_index)

    create index(:venues, [:place_id], name: :venues_place_id_index)
  end
end
