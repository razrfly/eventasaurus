defmodule EventasaurusApp.Repo.Migrations.AddCityIdConstraintsToVenues do
  use Ecto.Migration

  def up do
    # Pre-flight check: Ensure no venues missing city_id (except regions)
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM venues
        WHERE city_id IS NULL
          AND venue_type != 'region'
      ) THEN
        RAISE EXCEPTION 'Cannot add constraint: non-regional venues have NULL city_id';
      END IF;
    END $$;
    """

    # Add CHECK constraint (PostgreSQL doesn't support conditional NOT NULL)
    # Regional venues can have NULL city_id, all others must have city_id
    execute """
    ALTER TABLE venues
    ADD CONSTRAINT venues_city_id_required_for_non_regional
    CHECK (
      venue_type = 'region' OR city_id IS NOT NULL
    );
    """
  end

  def down do
    execute "ALTER TABLE venues DROP CONSTRAINT IF EXISTS venues_city_id_required_for_non_regional"
  end
end
