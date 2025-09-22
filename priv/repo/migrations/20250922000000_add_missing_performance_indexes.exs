defmodule EventasaurusApp.Repo.Migrations.AddMissingPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Add index on slug for show page lookups
    create_if_not_exists index(:public_events, [:slug])

    # Add composite index for price range queries
    create_if_not_exists index(:public_events, [:min_price, :max_price])

    # Add index on starts_at for date-based queries
    create_if_not_exists index(:public_events, [:starts_at])

    # Add composite index for common filter combinations
    create_if_not_exists index(:public_events, [:venue_id, :starts_at])

    # Add index for the search vector if not exists
    create_if_not_exists index(:public_events, [:search_vector], using: :gin)
  end
end