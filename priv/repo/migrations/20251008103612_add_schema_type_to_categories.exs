defmodule EventasaurusApp.Repo.Migrations.AddSchemaTypeToCategories do
  use Ecto.Migration

  def change do
    alter table(:categories) do
      add :schema_type, :string, default: "Event", null: false
    end

    # Backfill schema_type based on category slugs and their corresponding schema.org types

    # MusicEvent - Concerts and music festivals
    execute """
    UPDATE categories SET schema_type = 'MusicEvent'
    WHERE slug IN ('concerts');
    """, ""

    # Festival - Multi-day cultural celebrations
    execute """
    UPDATE categories SET schema_type = 'Festival'
    WHERE slug IN ('festivals');
    """, ""

    # TheaterEvent - Theater, musicals, stage performances
    execute """
    UPDATE categories SET schema_type = 'TheaterEvent'
    WHERE slug IN ('theatre');
    """, ""

    # SportsEvent - Sporting events and competitions
    execute """
    UPDATE categories SET schema_type = 'SportsEvent'
    WHERE slug = 'sports';
    """, ""

    # ComedyEvent - Stand-up comedy and humor shows
    execute """
    UPDATE categories SET schema_type = 'ComedyEvent'
    WHERE slug = 'comedy';
    """, ""

    # VisualArtsEvent - Art exhibitions and galleries
    execute """
    UPDATE categories SET schema_type = 'VisualArtsEvent'
    WHERE slug = 'arts';
    """, ""

    # ScreeningEvent - Movie screenings and cinema events
    execute """
    UPDATE categories SET schema_type = 'ScreeningEvent'
    WHERE slug = 'film';
    """, ""

    # ChildrensEvent - Family-friendly and children's events
    execute """
    UPDATE categories SET schema_type = 'ChildrensEvent'
    WHERE slug = 'family';
    """, ""

    # FoodEvent - Food festivals and culinary events
    execute """
    UPDATE categories SET schema_type = 'FoodEvent'
    WHERE slug = 'food-drink';
    """, ""

    # SocialEvent - Club events, parties, nightlife
    execute """
    UPDATE categories SET schema_type = 'SocialEvent'
    WHERE slug IN ('nightlife', 'community', 'trivia');
    """, ""

    # EducationEvent - Workshops, lectures, educational events
    execute """
    UPDATE categories SET schema_type = 'EducationEvent'
    WHERE slug = 'education';
    """, ""

    # BusinessEvent - Conferences, networking, business events
    execute """
    UPDATE categories SET schema_type = 'BusinessEvent'
    WHERE slug = 'business';
    """, ""

    # 'other' stays as generic 'Event'
  end
end
