defmodule EventasaurusApp.Repo.Migrations.AddRecentLocationsIndexes do
  use Ecto.Migration

  def up do
    # Composite index for efficient event_users queries by user_id
    # This optimizes the main query in get_recent_locations_for_user
    create index(:event_users, [:user_id, :event_id], name: :event_users_user_id_event_id_idx)

    # Index for events filtering by venue_id (for physical venues)
    # This optimizes the join condition with venues
    create index(:events, [:venue_id], name: :events_venue_id_idx, where: "venue_id IS NOT NULL")

    # Index for events filtering by virtual_venue_url (to exclude virtual events)
    # This optimizes the WHERE clause that filters out virtual events
    create index(:events, [:virtual_venue_url], name: :events_virtual_venue_url_idx, where: "virtual_venue_url IS NULL")

    # Composite index for events by venue_id and inserted_at for sorting
    # This optimizes both the venue lookup and the recency sorting
    create index(:events, [:venue_id, :inserted_at], name: :events_venue_id_inserted_at_idx, where: "venue_id IS NOT NULL")

    # Index for efficient venue lookups (already might exist, but ensure it's there)
    create_if_not_exists index(:venues, [:id], name: :venues_id_idx)

    # Index for venue name searches (for address-based venue matching)
    create_if_not_exists index(:venues, [:address], name: :venues_address_idx)
  end

  def down do
    drop_if_exists index(:event_users, [:user_id, :event_id], name: :event_users_user_id_event_id_idx)
    drop_if_exists index(:events, [:venue_id], name: :events_venue_id_idx)
    drop_if_exists index(:events, [:virtual_venue_url], name: :events_virtual_venue_url_idx)
    drop_if_exists index(:events, [:venue_id, :inserted_at], name: :events_venue_id_inserted_at_idx)
    drop_if_exists index(:venues, [:id], name: :venues_id_idx)
    drop_if_exists index(:venues, [:address], name: :venues_address_idx)
  end
end
