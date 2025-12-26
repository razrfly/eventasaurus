defmodule EventasaurusApp.Repo.Migrations.RefactorCachedImagesSchema do
  use Ecto.Migration

  def change do
    # Drop the old unique index that used image_role
    drop_if_exists unique_index(:cached_images, [:entity_type, :entity_id, :image_role])

    alter table(:cached_images) do
      # Remove unused/redundant fields
      remove :image_role, :string
      remove :cached_at, :utc_datetime_usec
      remove :expires_at, :utc_datetime_usec

      # Add position for ordering (replaces image_role)
      add :position, :integer, null: false, default: 0
    end

    # New unique constraint: one image per entity+position
    create unique_index(:cached_images, [:entity_type, :entity_id, :position])
  end
end
