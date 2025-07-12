defmodule EventasaurusApp.Repo.Migrations.UpdatePollTypeRestaurantToPlaces do
  use Ecto.Migration

  def up do
    # Since there are no existing restaurant polls to migrate,
    # we just need to update any database constraints or enums if they exist

    # Check if there are any polls with restaurant type and log a warning if found
    execute "DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM polls WHERE poll_type = 'restaurant') THEN
        RAISE NOTICE 'Warning: Found existing restaurant polls. Manual data migration may be needed.';
      END IF;
    END $$;"

    # No actual data migration needed since user confirmed no restaurant polls exist
  end

  def down do
    # Reverse operation - this would change places back to restaurant if needed
    # Since this is a breaking change, we'll just log a notice
    execute "SELECT 1" # No-op, since this is essentially irreversible without data loss
  end
end
