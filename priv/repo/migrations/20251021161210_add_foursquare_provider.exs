defmodule EventasaurusApp.Repo.Migrations.AddFoursquareProvider do
  use Ecto.Migration

  def up do
    # Add Foursquare as a new multi-capability provider
    # Priority 2 for geocoding (slightly lower than free tier providers)
    # Priority 5 for images (mid-tier, good quality but rate limited)
    execute """
    INSERT INTO geocoding_providers (name, priority, is_active, metadata, capabilities, priorities, inserted_at, updated_at)
    VALUES (
      'foursquare',
      2,
      true,
      '{"rate_limits": {"per_second": 1, "per_minute": 60, "per_hour": 500}, "timeout_ms": 10000}'::jsonb,
      '{"geocoding": true, "images": true, "reviews": false, "hours": false}'::jsonb,
      '{"geocoding": 2, "images": 5}'::jsonb,
      NOW(),
      NOW()
    );
    """
  end

  def down do
    execute "DELETE FROM geocoding_providers WHERE name = 'foursquare';"
  end
end
