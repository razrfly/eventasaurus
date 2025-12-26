defmodule EventasaurusApp.Repo.Migrations.CreateCachedImages do
  use Ecto.Migration

  def change do
    create table(:cached_images) do
      # Polymorphic association - which entity owns this image
      add :entity_type, :string, null: false
      add :entity_id, :bigint, null: false
      add :image_role, :string, null: false

      # Source tracking
      add :original_url, :text, null: false
      add :original_source, :string

      # R2 storage
      add :r2_key, :string, size: 500
      add :cdn_url, :text

      # Status tracking
      add :status, :string, default: "pending", null: false
      add :retry_count, :integer, default: 0, null: false
      add :last_error, :text

      # Metadata
      add :content_type, :string, size: 100
      add :file_size, :bigint
      add :width, :integer
      add :height, :integer
      add :metadata, :map, default: %{}

      # Cache timing
      add :cached_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint: one cached image per entity+role combination
    create unique_index(:cached_images, [:entity_type, :entity_id, :image_role])

    # Find cached version of a specific URL
    create index(:cached_images, [:original_url])

    # Query by status for retry jobs, cleanup, etc.
    create index(:cached_images, [:status])

    # Lookup by R2 key for deletion/management
    create index(:cached_images, [:r2_key])

    # Find all images for an entity
    create index(:cached_images, [:entity_type, :entity_id])
  end
end
