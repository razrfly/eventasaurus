defmodule EventasaurusApp.Repo.Migrations.MigrateAggregationTypesToSchemaOrg do
  use Ecto.Migration

  def up do
    # Migrate existing aggregation_type values to schema.org event types
    execute """
    UPDATE sources
    SET aggregation_type = CASE aggregation_type
      WHEN 'restaurant' THEN 'FoodEvent'
      WHEN 'movie' THEN 'ScreeningEvent'
      WHEN 'concert' THEN 'MusicEvent'
      WHEN 'events' THEN 'Event'
      ELSE aggregation_type
    END
    WHERE aggregation_type IN ('restaurant', 'movie', 'concert', 'events')
    """
  end

  def down do
    # Reverse migration: convert schema.org types back to custom types
    execute """
    UPDATE sources
    SET aggregation_type = CASE aggregation_type
      WHEN 'FoodEvent' THEN 'restaurant'
      WHEN 'ScreeningEvent' THEN 'movie'
      WHEN 'MusicEvent' THEN 'concert'
      WHEN 'Event' THEN 'events'
      ELSE aggregation_type
    END
    WHERE aggregation_type IN ('FoodEvent', 'ScreeningEvent', 'MusicEvent', 'Event')
    """
  end
end
