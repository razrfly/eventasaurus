defmodule EventasaurusApp.Repo.Migrations.UpdatePollOptionsUniqueConstraintForPlaces do
  use Ecto.Migration

  def up do
    # Drop the existing unique index that only checks title
    drop unique_index(:poll_options, [:poll_id, :suggested_by_id, :title], 
      name: :poll_options_unique_per_user)
    
    # Create a new unique index that includes place_id for places
    # This allows multiple places with the same name but different place_ids
    execute """
    CREATE UNIQUE INDEX poll_options_unique_per_user 
    ON poll_options (
      poll_id,
      suggested_by_id,
      title,
      (external_data->>'place_id')
    )
    """
  end

  def down do
    # Drop the new index
    drop index(:poll_options, name: :poll_options_unique_per_user)
    
    # Recreate the original index
    create unique_index(:poll_options, [:poll_id, :suggested_by_id, :title], 
      name: :poll_options_unique_per_user)
  end
end