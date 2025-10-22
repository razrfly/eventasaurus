defmodule EventasaurusApp.Repo.Migrations.RemoveGeoapifyImageCapability do
  use Ecto.Migration

  def up do
    # Remove incorrect "images" capability from Geoapify
    # Geoapify does not provide an images/photos API according to their documentation
    execute """
    UPDATE venue_data_providers
    SET capabilities = capabilities - 'images'
    WHERE name = 'geoapify';
    """

    # Also remove the images priority that was incorrectly set
    execute """
    UPDATE venue_data_providers
    SET priorities = priorities - 'images'
    WHERE name = 'geoapify';
    """
  end

  def down do
    # Restore previous (incorrect) state if migration needs to be rolled back
    execute """
    UPDATE venue_data_providers
    SET capabilities = jsonb_set(capabilities, '{images}', 'true')
    WHERE name = 'geoapify';
    """

    execute """
    UPDATE venue_data_providers
    SET priorities = jsonb_set(priorities, '{images}', '10')
    WHERE name = 'geoapify';
    """
  end
end
