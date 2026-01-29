defmodule EventasaurusApp.Repo.Migrations.CreateCategoryMappings do
  use Ecto.Migration

  def change do
    create table(:category_mappings) do
      # Source identifier (e.g., "bandsintown", "karnet", "_defaults")
      add :source, :string, null: false, size: 50

      # The external term to match (e.g., "Rock", "koncerty", "music.*festival")
      add :external_term, :string, null: false, size: 255

      # Mapping type: "direct" for exact match, "pattern" for regex
      add :mapping_type, :string, null: false, size: 20

      # Target category slug (e.g., "concerts", "theatre")
      add :category_slug, :string, null: false, size: 100

      # Priority for pattern matching (higher = checked first)
      add :priority, :integer, default: 0, null: false

      # Soft delete / disable without removing
      add :is_active, :boolean, default: true, null: false

      # Track who created/modified (nullable for YAML imports)
      add :created_by_id, references(:users, on_delete: :nilify_all)

      # Additional metadata (e.g., notes, confidence score for ML)
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Unique constraint: one mapping per source + term + type combination
    create unique_index(:category_mappings, [:source, :external_term, :mapping_type],
      name: :category_mappings_source_term_type_unique
    )

    # Index for fast lookups by source
    create index(:category_mappings, [:source])

    # Index for looking up by category (useful for admin UI)
    create index(:category_mappings, [:category_slug])

    # Index for active mappings only (most common query pattern)
    create index(:category_mappings, [:source, :is_active],
      where: "is_active = true",
      name: :category_mappings_active_by_source
    )

    # Index for pattern mappings ordered by priority
    create index(:category_mappings, [:source, :mapping_type, :priority],
      where: "mapping_type = 'pattern'",
      name: :category_mappings_patterns_by_priority
    )
  end
end
