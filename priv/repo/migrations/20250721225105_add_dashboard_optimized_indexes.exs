defmodule EventasaurusApp.Repo.Migrations.AddDashboardOptimizedIndexes do
  use Ecto.Migration

  def change do
    # Composite indexes for the optimized LEFT JOIN query
    create_if_not_exists index(:event_users, [:event_id, :user_id], name: :event_users_event_user_composite_idx)
    create_if_not_exists index(:event_participants, [:event_id, :user_id, :status], name: :event_participants_event_user_status_idx)
    
    # Partial indexes for common queries
    # For upcoming/past filtering, we can't use NOW() in index predicates
    # Instead, create indexes that help with the time comparisons
    create_if_not_exists index(:events, [:start_at, :deleted_at], 
      where: "deleted_at IS NULL",
      name: :events_start_at_active_idx)
    
    # Index for NULL start_at (upcoming events without date)
    create_if_not_exists index(:events, [:id], 
      where: "deleted_at IS NULL AND start_at IS NULL",
      name: :events_no_start_date_idx)
    
    # Index for deleted_at filtering on main query
    create_if_not_exists index(:events, [:deleted_at], 
      where: "deleted_at IS NULL",
      name: :events_active_idx)
    
    # Index for venue joins
    create_if_not_exists index(:venues, [:id], name: :venues_id_idx)
    
    # Covering index for event participant queries
    create_if_not_exists index(:event_participants, [:event_id], 
      where: "deleted_at IS NULL",
      name: :event_participants_active_idx)
  end
end