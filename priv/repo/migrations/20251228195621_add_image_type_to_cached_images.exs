defmodule EventasaurusApp.Repo.Migrations.AddImageTypeToCachedImages do
  use Ecto.Migration

  @doc """
  Adds `image_type` column for semantic image discrimination.

  This allows distinguishing between different types of images for the same entity:
  - Movies: poster, backdrop, still, logo
  - Other entities: primary (default)

  Existing records get `image_type = 'primary'` as the default.

  The unique constraint is updated to include image_type, allowing multiple
  images of different types at the same position (e.g., poster at position 0
  AND backdrop at position 0).
  """

  def change do
    # Add image_type column with default 'primary'
    # This automatically backfills existing records
    alter table(:cached_images) do
      add :image_type, :string, default: "primary", null: false
    end

    # Drop old unique constraint (entity_type, entity_id, position)
    drop_if_exists unique_index(:cached_images, [:entity_type, :entity_id, :position])

    # Create new unique constraint including image_type
    # Allows: movie_123/poster/0, movie_123/backdrop/0, movie_123/poster/1
    create unique_index(:cached_images, [:entity_type, :entity_id, :image_type, :position])

    # Add index for querying by image_type
    create index(:cached_images, [:entity_type, :entity_id, :image_type])
  end
end
