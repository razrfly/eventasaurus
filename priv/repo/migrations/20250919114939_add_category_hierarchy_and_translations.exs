defmodule Eventasaurus.Repo.Migrations.AddCategoryHierarchyAndTranslations do
  use Ecto.Migration

  def change do
    # Add new fields to categories table
    alter table(:categories) do
      add :parent_id, references(:categories, on_delete: :restrict)
      add :translations, :jsonb, default: "{}"
      add :is_active, :boolean, default: true
    end

    # Create indexes for efficient queries
    create index(:categories, [:parent_id])
    create index(:categories, [:is_active])
    create index(:categories, [:translations], using: :gin)

    # Create index for Polish language queries (our primary second language)
    execute """
    CREATE INDEX idx_categories_polish_name ON categories
    USING btree ((translations -> 'pl' ->> 'name'))
    """,
    "DROP INDEX idx_categories_polish_name"

    # Create many-to-many relationship table
    create table(:public_event_categories) do
      add :event_id, references(:public_events, on_delete: :delete_all), null: false
      add :category_id, references(:categories, on_delete: :restrict), null: false
      add :is_primary, :boolean, default: false
      add :source, :string, size: 50
      add :confidence, :float, default: 1.0

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:public_event_categories, [:event_id, :category_id])
    create index(:public_event_categories, [:event_id])
    create index(:public_event_categories, [:category_id])
    create index(:public_event_categories, [:is_primary])
    create index(:public_event_categories, [:source])

    # Create external category mappings table
    create table(:category_mappings) do
      add :external_source, :string, size: 50, null: false
      add :external_type, :string, size: 50
      add :external_value, :string, null: false
      add :external_locale, :string, size: 5, default: "en"
      add :category_id, references(:categories, on_delete: :restrict), null: false
      add :priority, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:category_mappings, [:external_source, :external_type, :external_value])
    create index(:category_mappings, [:external_source])
    create index(:category_mappings, [:category_id])
    create index(:category_mappings, [:priority])

    # Create backward compatibility view
    # Using column list to avoid duplicate category_id
    execute """
    CREATE OR REPLACE VIEW public_events_with_category AS
    SELECT
      pe.id,
      pe.title,
      pe.slug,
      pe.description,
      pe.starts_at,
      pe.ends_at,
      pe.external_id,
      pe.ticket_url,
      pe.min_price,
      pe.max_price,
      pe.currency,
      pe.metadata,
      pe.venue_id,
      pe.inserted_at,
      pe.updated_at,
      COALESCE(pec.category_id, pe.category_id) as category_id
    FROM public_events pe
    LEFT JOIN public_event_categories pec
      ON pe.id = pec.event_id
      AND pec.is_primary = true
    """,
    "DROP VIEW IF EXISTS public_events_with_category"

    # Add Polish translations to existing categories
    execute """
    UPDATE categories SET translations =
    CASE slug
      WHEN 'festivals' THEN '{"pl": {"name": "Festiwale", "description": "Festiwale muzyczne, kulturalne i wielodniowe wydarzenia"}}'::jsonb
      WHEN 'concerts' THEN '{"pl": {"name": "Koncerty", "description": "Występy muzyczne na żywo i pokazy"}}'::jsonb
      WHEN 'performances' THEN '{"pl": {"name": "Spektakle", "description": "Teatr, taniec, komedia i inne występy na żywo"}}'::jsonb
      WHEN 'literature' THEN '{"pl": {"name": "Literatura", "description": "Czytania książek, spotkania autorskie i wydarzenia literackie"}}'::jsonb
      WHEN 'film' THEN '{"pl": {"name": "Film", "description": "Pokazy filmowe, festiwale filmowe i wydarzenia kinowe"}}'::jsonb
      WHEN 'exhibitions' THEN '{"pl": {"name": "Wystawy", "description": "Wystawy sztuki, pokazy muzealne i wydarzenia galeryjne"}}'::jsonb
      ELSE '{}'::jsonb
    END
    WHERE slug IN ('festivals', 'concerts', 'performances', 'literature', 'film', 'exhibitions')
    """,
    ""

    # Migrate existing category relationships to new join table
    # This preserves existing data while we transition
    execute """
    INSERT INTO public_event_categories (event_id, category_id, is_primary, source, confidence, inserted_at)
    SELECT
      id as event_id,
      category_id,
      true as is_primary,
      'migration' as source,
      1.0 as confidence,
      NOW() as inserted_at
    FROM public_events
    WHERE category_id IS NOT NULL
    ON CONFLICT (event_id, category_id) DO NOTHING
    """,
    "DELETE FROM public_event_categories WHERE source = 'migration'"
  end
end