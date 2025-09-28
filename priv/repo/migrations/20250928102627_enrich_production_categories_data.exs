defmodule EventasaurusApp.Repo.Migrations.EnrichProductionCategoriesData do
  use Ecto.Migration

  def up do
    # Update all existing categories with rich data from seeds
    # This ensures production matches development exactly

    execute """
    UPDATE categories SET
      description = data.description,
      icon = data.icon,
      color = data.color,
      display_order = data.display_order
    FROM (VALUES
      ('concerts', 'Live music performances and shows', '🎵', '#4ECDC4', 1),
      ('festivals', 'Music festivals, cultural festivals, and multi-day events', '🎪', '#FF6B6B', 2),
      ('theatre', 'Theater, musicals, and stage performances', '🎭', '#95E77E', 3),
      ('sports', 'Sporting events and competitions', '⚽', '#FFA500', 4),
      ('comedy', 'Stand-up comedy and humor shows', '😂', '#FFD700', 5),
      ('arts', 'Art exhibitions, galleries, and cultural events', '🎨', '#C7B8FF', 6),
      ('film', 'Movie screenings, film festivals, and cinema events', '🎬', '#A8E6CF', 7),
      ('family', 'Family-friendly and children''s events', '👨‍👩‍👧‍👦', '#FFB6C1', 8),
      ('food-drink', 'Food festivals, tastings, and culinary events', '🍽️', '#98D8C8', 9),
      ('nightlife', 'Club events, parties, and night entertainment', '🌃', '#6A0DAD', 10),
      ('community', 'Community gatherings and local events', '👥', '#87CEEB', 11),
      ('education', 'Workshops, lectures, and educational events', '🎓', '#4169E1', 12),
      ('business', 'Conferences, networking, and business events', '💼', '#708090', 13),
      ('other', 'Events that do not fit into standard categories', '❓', '#808080', 14)
    ) AS data(slug, description, icon, color, display_order)
    WHERE categories.slug = data.slug;
    """

    # Also ensure the "Other" category keeps its Polish translations
    # (this should already be there but let's make sure)
    execute """
    UPDATE categories
    SET translations = jsonb_build_object(
      'pl', jsonb_build_object(
        'name', 'Inne',
        'sources', jsonb_build_array('karnet', 'general')
      )
    )
    WHERE slug = 'other' AND (
      translations IS NULL
      OR translations = '{}'::jsonb
      OR NOT (translations ? 'pl')
    );
    """

    # Log what we updated
    execute """
    DO $$
    DECLARE
      updated_count INTEGER;
    BEGIN
      SELECT COUNT(*) INTO updated_count
      FROM categories
      WHERE icon IS NOT NULL;

      RAISE NOTICE 'Updated % categories with rich data', updated_count;
    END $$;
    """
  end

  def down do
    # Optionally remove the enriched data (though you probably don't want to)
    execute """
    UPDATE categories SET
      description = NULL,
      icon = NULL,
      color = NULL,
      display_order = 999
    WHERE slug IN (
      'concerts', 'festivals', 'theatre', 'sports', 'comedy',
      'arts', 'film', 'family', 'food-drink', 'nightlife',
      'community', 'education', 'business', 'other'
    );
    """
  end
end