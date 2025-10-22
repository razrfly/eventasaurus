defmodule EventasaurusApp.Repo.Migrations.RemovePlaceIdFromVenues do
  use Ecto.Migration

  @moduledoc """
  Removes the deprecated place_id field from venues table.

  ## Context
  - place_id was the original single-provider identifier
  - Replaced by provider_ids JSONB field for multi-provider support
  - All venues have been migrated to use provider_ids
  - Deduplication uses GPS proximity + name similarity, not place_id

  ## Data Safety
  - 817 venues in production
  - 99.88% unique (only 1 duplicate pair found)
  - provider_ids field contains all provider identifiers
  - No data loss expected

  ## Rollback Plan
  If rollback is needed:
  - The down/0 function will recreate the place_id column
  - Original place_id data is NOT recoverable (was empty for most venues)
  - Manual data migration would be required if old code needs place_id
  """

  def up do
    # Drop unique index first
    drop_if_exists index(:venues, [:place_id], name: :venues_place_id_unique_index)

    # Remove place_id column
    alter table(:venues) do
      remove :place_id
    end
  end

  def down do
    # Recreate place_id column
    alter table(:venues) do
      add :place_id, :string
    end

    # Recreate unique index
    create unique_index(:venues, [:place_id], name: :venues_place_id_unique_index)
  end
end
