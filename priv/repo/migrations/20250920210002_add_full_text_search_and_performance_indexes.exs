defmodule EventasaurusApp.Repo.Migrations.AddFullTextSearchAndPerformanceIndexes do
  use Ecto.Migration

  def up do
    # Enable required extensions
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"
    execute "CREATE EXTENSION IF NOT EXISTS unaccent"

    # Add search vector column to public_events
    alter table(:public_events) do
      add :search_vector, :tsvector
    end

    # Create GIN indexes for full-text search
    create index(:public_events, [:search_vector], using: :gin)

    # Create trigram indexes for fuzzy search on title
    execute """
    CREATE INDEX public_events_title_trgm_idx
    ON public_events USING gin(title gin_trgm_ops)
    """

    # Create function to update search vector with multi-language support
    execute """
    CREATE OR REPLACE FUNCTION update_public_events_search_vector()
    RETURNS trigger AS $$
    BEGIN
      NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.title_translations::text, '')), 'B');
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create trigger to automatically update search vector
    execute """
    CREATE TRIGGER update_search_vector
    BEFORE INSERT OR UPDATE ON public_events
    FOR EACH ROW EXECUTE FUNCTION update_public_events_search_vector();
    """

    # Update existing records
    execute """
    UPDATE public_events
    SET search_vector =
      setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
      setweight(to_tsvector('english', COALESCE(title_translations::text, '')), 'B')
    """

    # Additional performance indexes for common query patterns
    # Composite indexes for filtering combinations
    create_if_not_exists index(:public_events, [:starts_at, :category_id])
    create_if_not_exists index(:public_events, [:venue_id, :starts_at])
    create_if_not_exists index(:public_events, [:min_price, :max_price])

    # Indexes for public_event_sources priority sorting
    execute """
    CREATE INDEX IF NOT EXISTS idx_public_event_sources_priority
    ON public_event_sources ((COALESCE(
      CASE
        WHEN (metadata->>'priority') ~ '^[0-9]+$' THEN (metadata->>'priority')::integer
        ELSE NULL
      END, 10
    )))
    """
  end

  def down do
    # Remove trigger and function
    execute "DROP TRIGGER IF EXISTS update_search_vector ON public_events"
    execute "DROP FUNCTION IF EXISTS update_public_events_search_vector()"

    # Remove indexes
    execute "DROP INDEX IF EXISTS public_events_title_trgm_idx"
    execute "DROP INDEX IF EXISTS idx_public_event_sources_priority"
    drop_if_exists index(:public_events, [:search_vector])
    drop_if_exists index(:public_events, [:starts_at, :category_id])
    drop_if_exists index(:public_events, [:venue_id, :starts_at])
    drop_if_exists index(:public_events, [:min_price, :max_price])

    # Remove column
    alter table(:public_events) do
      remove :search_vector
    end
  end
end