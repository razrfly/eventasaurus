defmodule EventasaurusApp.Repo.Migrations.RefactorCachedImagesSchema do
  use Ecto.Migration

  def change do
    # Drop the old unique index that used image_role
    drop_if_exists unique_index(:cached_images, [:entity_type, :entity_id, :image_role])

    alter table(:cached_images) do
      # Remove unused/redundant fields (with types for reversibility)
      remove :image_role, :string
      remove :cached_at, :utc_datetime_usec
      remove :expires_at, :utc_datetime_usec

      # Add position for ordering (replaces image_role)
      add :position, :integer, null: false, default: 0
    end

    # Assign unique positions to any existing rows before creating constraint.
    # Groups by (entity_type, entity_id) and assigns sequential positions.
    # This is a no-op if the table is empty.
    execute(
      """
      WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (
          PARTITION BY entity_type, entity_id
          ORDER BY inserted_at ASC
        ) - 1 AS new_position
        FROM cached_images
      )
      UPDATE cached_images
      SET position = ranked.new_position
      FROM ranked
      WHERE cached_images.id = ranked.id
      """,
      # Down migration: no-op, positions don't need to be reset
      "SELECT 1"
    )

    # New unique constraint: one image per entity+position
    create unique_index(:cached_images, [:entity_type, :entity_id, :position])
  end
end
