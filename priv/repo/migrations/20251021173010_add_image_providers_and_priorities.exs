defmodule EventasaurusApp.Repo.Migrations.AddImageProvidersAndPriorities do
  use Ecto.Migration

  def up do
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
    # Remove images priority from providers
    execute """
    UPDATE venue_data_providers
    SET priorities = priorities - 'images'
    WHERE name IN ('geoapify', 'here', 'google_places');
    """
  end
end
