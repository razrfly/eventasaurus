defmodule EventasaurusApp.Repo.Migrations.AddCoreCategoriesData do
  use Ecto.Migration

  def up do
    # Core categories that the application depends on
    # These are inserted idempotently using ON CONFLICT DO NOTHING
    execute """
    INSERT INTO categories (name, slug, description, icon, color, display_order, inserted_at, updated_at) VALUES
      ('Concerts', 'concerts', 'Live music performances and shows', '🎵', '#4ECDC4', 1, NOW(), NOW()),
      ('Festivals', 'festivals', 'Music festivals, cultural festivals, and multi-day events', '🎪', '#FF6B6B', 2, NOW(), NOW()),
      ('Theatre', 'theatre', 'Theater, musicals, and stage performances', '🎭', '#95E77E', 3, NOW(), NOW()),
      ('Sports', 'sports', 'Sporting events and competitions', '⚽', '#FFA500', 4, NOW(), NOW()),
      ('Comedy', 'comedy', 'Stand-up comedy and humor shows', '😂', '#FFD700', 5, NOW(), NOW()),
      ('Arts', 'arts', 'Art exhibitions, galleries, and cultural events', '🎨', '#C7B8FF', 6, NOW(), NOW()),
      ('Film', 'film', 'Movie screenings, film festivals, and cinema events', '🎬', '#A8E6CF', 7, NOW(), NOW()),
      ('Family', 'family', 'Family-friendly and children''s events', '👨‍👩‍👧‍👦', '#FFB6C1', 8, NOW(), NOW()),
      ('Food & Drink', 'food-drink', 'Food festivals, tastings, and culinary events', '🍽️', '#98D8C8', 9, NOW(), NOW()),
      ('Nightlife', 'nightlife', 'Club events, parties, and night entertainment', '🌃', '#6A0DAD', 10, NOW(), NOW()),
      ('Community', 'community', 'Community gatherings and local events', '👥', '#87CEEB', 11, NOW(), NOW()),
      ('Education', 'education', 'Workshops, lectures, and educational events', '🎓', '#4169E1', 12, NOW(), NOW()),
      ('Business', 'business', 'Conferences, networking, and business events', '💼', '#708090', 13, NOW(), NOW()),
      ('Other', 'other', 'Uncategorized events', '📌', '#808080', 999, NOW(), NOW())
    ON CONFLICT (slug) DO NOTHING;
    """

    # Add core category mappings for Ticketmaster
    execute """
    INSERT INTO category_mappings (external_source, external_type, external_value, external_locale, category_id, priority, inserted_at, updated_at)
    SELECT 'ticketmaster', type, value, 'en', cat.id, priority, NOW(), NOW()
    FROM (VALUES
      ('segment', 'Music', 'concerts', 100),
      ('genre', 'Rock', 'concerts', 90),
      ('genre', 'Pop', 'concerts', 90),
      ('genre', 'Alternative', 'concerts', 90),
      ('genre', 'Country', 'concerts', 90),
      ('genre', 'Hip-Hop/Rap', 'concerts', 90),
      ('genre', 'R&B', 'concerts', 90),
      ('genre', 'Electronic', 'concerts', 90),
      ('genre', 'Jazz', 'concerts', 90),
      ('genre', 'Blues', 'concerts', 90),
      ('genre', 'Classical', 'concerts', 90),
      ('genre', 'Metal', 'concerts', 90),
      ('genre', 'Indie', 'concerts', 90),
      ('segment', 'Sports', 'sports', 100),
      ('genre', 'Basketball', 'sports', 90),
      ('genre', 'Football', 'sports', 90),
      ('genre', 'Baseball', 'sports', 90),
      ('genre', 'Hockey', 'sports', 90),
      ('genre', 'Soccer', 'sports', 90),
      ('segment', 'Arts & Theatre', 'theatre', 100),
      ('genre', 'Theatre', 'theatre', 90),
      ('genre', 'Musical', 'theatre', 90),
      ('genre', 'Opera', 'arts', 90),
      ('genre', 'Dance', 'arts', 90),
      ('genre', 'Comedy', 'comedy', 90),
      ('segment', 'Family', 'family', 100),
      ('genre', 'Children''s Theatre', 'family', 90),
      ('segment', 'Film', 'film', 100)
    ) AS t(type, value, slug, priority)
    JOIN categories cat ON cat.slug = t.slug
    ON CONFLICT (external_source, external_type, external_value, external_locale) DO NOTHING;
    """

    # Add core category mappings for Karnet (Polish)
    execute """
    INSERT INTO category_mappings (external_source, external_type, external_value, external_locale, category_id, priority, inserted_at, updated_at)
    SELECT 'karnet', NULL, value, 'pl', cat.id, priority, NOW(), NOW()
    FROM (VALUES
      ('koncerty', 'concerts', 100),
      ('teatr', 'theatre', 100),
      ('spektakle', 'theatre', 90),
      ('kabaret', 'comedy', 100),
      ('stand-up', 'comedy', 100),
      ('festiwale', 'festivals', 100),
      ('imprezy', 'nightlife', 80),
      ('sport', 'sports', 100),
      ('film', 'film', 100),
      ('kino', 'film', 100),
      ('sztuka', 'arts', 100),
      ('wystawa', 'arts', 90),
      ('muzyka', 'concerts', 90),
      ('opera', 'arts', 100),
      ('balet', 'arts', 100),
      ('taniec', 'arts', 90),
      ('dla-dzieci', 'family', 100),
      ('warsztaty', 'education', 100),
      ('konferencje', 'business', 100)
    ) AS t(value, slug, priority)
    JOIN categories cat ON cat.slug = t.slug
    ON CONFLICT (external_source, external_type, external_value, external_locale) DO NOTHING;
    """

    # Add core category mappings for Bandsintown
    execute """
    INSERT INTO category_mappings (external_source, external_type, external_value, external_locale, category_id, priority, inserted_at, updated_at)
    SELECT 'bandsintown', NULL, value, 'en', cat.id, priority, NOW(), NOW()
    FROM (VALUES
      ('concert', 'concerts', 100),
      ('festival', 'festivals', 100),
      ('music', 'concerts', 100),
      ('rock', 'concerts', 90),
      ('pop', 'concerts', 90),
      ('metal', 'concerts', 90),
      ('jazz', 'concerts', 90),
      ('electronic', 'concerts', 90),
      ('hip-hop', 'concerts', 90),
      ('indie', 'concerts', 90),
      ('punk', 'concerts', 90),
      ('alternative', 'concerts', 90),
      ('country', 'concerts', 90),
      ('folk', 'concerts', 90),
      ('blues', 'concerts', 90),
      ('classical', 'concerts', 90)
    ) AS t(value, slug, priority)
    JOIN categories cat ON cat.slug = t.slug
    ON CONFLICT (external_source, external_type, external_value, external_locale) DO NOTHING;
    """
  end

  def down do
    # Since we don't have a metadata column to track which mappings
    # were added by the migration, we'll be conservative and only
    # provide a comment about manual cleanup if needed.
    # We don't remove categories or mappings in down migration as they
    # might have associated data by the time we rollback.
  end
end