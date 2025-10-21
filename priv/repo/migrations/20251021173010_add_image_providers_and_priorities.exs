defmodule EventasaurusApp.Repo.Migrations.AddImageProvidersAndPriorities do
  use Ecto.Migration

  def up do
    # Add Unsplash as a fallback image provider
    execute """
    INSERT INTO venue_data_providers (name, is_active, capabilities, priorities, metadata, inserted_at, updated_at)
    VALUES (
      'unsplash',
      true,
      '{"images": true}',
      '{"images": 99}',
      '{"rate_limit": "50/hour", "free_tier": true, "requires_attribution": true}',
      NOW(),
      NOW()
    )
    ON CONFLICT (name) DO NOTHING;
    """

    # Update Geoapify to add images priority
    execute """
    UPDATE venue_data_providers
    SET priorities = jsonb_set(priorities, '{images}', '10')
    WHERE name = 'geoapify';
    """

    # Update HERE to add images priority (already has capability)
    execute """
    UPDATE venue_data_providers
    SET priorities = jsonb_set(priorities, '{images}', '3')
    WHERE name = 'here';
    """

    # Update Google Places to set images priority (currently inactive but configured)
    execute """
    UPDATE venue_data_providers
    SET priorities = jsonb_set(priorities, '{images}', '1')
    WHERE name = 'google_places';
    """
  end

  def down do
    # Remove Unsplash provider
    execute "DELETE FROM venue_data_providers WHERE name = 'unsplash';"

    # Remove images priority from providers
    execute """
    UPDATE venue_data_providers
    SET priorities = priorities - 'images'
    WHERE name IN ('geoapify', 'here', 'google_places');
    """
  end
end
