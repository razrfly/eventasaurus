defmodule EventasaurusApp.Repo.Migrations.BackfillProvidedCoordinatesPerformance do
  use Ecto.Migration

  def up do
    # Backfill geocoding_performance for venues with provided coordinates
    # These venues have data in metadata->'geocoding' but NULL geocoding_performance
    execute """
    UPDATE venues
    SET geocoding_performance = jsonb_build_object(
      'provider', metadata->'geocoding'->>'provider',
      'source_scraper', COALESCE(metadata->'geocoding'->>'source_scraper', 'unknown_scraper'),
      'geocoded_at', metadata->'geocoding'->'geocoded_at',
      'cost_per_call', 0.0,
      'attempts', 0,
      'attempted_providers', '[]'::jsonb
    )
    WHERE metadata->'geocoding'->>'provider' = 'provided'
      AND geocoding_performance IS NULL;
    """

    # Update source field to 'provided' for these venues to distinguish them from scraped venues
    execute """
    UPDATE venues
    SET source = 'provided'
    WHERE metadata->'geocoding'->>'provider' = 'provided'
      AND source = 'scraper';
    """
  end

  def down do
    # Note: This assumes all 'provided' sources were originally 'scraper'.
    # If any venues had other original sources before being set to 'provided',
    # they will be incorrectly set to 'scraper' during rollback.
    # This is a known limitation of simple reversible migrations.

    # Revert source field changes
    execute """
    UPDATE venues
    SET source = 'scraper'
    WHERE source = 'provided';
    """

    # Revert geocoding_performance changes
    execute """
    UPDATE venues
    SET geocoding_performance = NULL
    WHERE metadata->'geocoding'->>'provider' = 'provided'
      AND geocoding_performance IS NOT NULL;
    """
  end
end
