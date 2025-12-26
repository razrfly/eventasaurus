defmodule EventasaurusApp.Repo.Migrations.AddGetEntityImageUrlFunction do
  use Ecto.Migration

  def up do
    # SQL function for getting entity image URLs
    # Used by satellite sites that query the database directly
    execute """
    CREATE OR REPLACE FUNCTION get_entity_image_url(
      p_entity_type TEXT,
      p_entity_id INTEGER,
      p_position INTEGER DEFAULT 0
    )
    RETURNS TEXT AS $$
    BEGIN
      RETURN (
        SELECT COALESCE(cdn_url, original_url)
        FROM cached_images
        WHERE entity_type = p_entity_type
          AND entity_id = p_entity_id
          AND position = p_position
          AND status = 'cached'
        LIMIT 1
      );
    END;
    $$ LANGUAGE plpgsql STABLE;
    """

    # Convenience function for venues by slug (most common use case)
    execute """
    CREATE OR REPLACE FUNCTION get_venue_image_url(
      p_venue_slug TEXT,
      p_position INTEGER DEFAULT 0
    )
    RETURNS TEXT AS $$
    DECLARE
      v_venue_id INTEGER;
    BEGIN
      SELECT id INTO v_venue_id FROM venues WHERE slug = p_venue_slug;

      IF v_venue_id IS NULL THEN
        RETURN NULL;
      END IF;

      RETURN get_entity_image_url('venue', v_venue_id, p_position);
    END;
    $$ LANGUAGE plpgsql STABLE;
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS get_venue_image_url(TEXT, INTEGER);"
    execute "DROP FUNCTION IF EXISTS get_entity_image_url(TEXT, INTEGER, INTEGER);"
  end
end
