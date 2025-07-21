defmodule EventasaurusApp.Repo.Migrations.AddDashboardPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Composite indexes for the UNION query
    create_if_not_exists index(:event_users, [:user_id, :event_id])
    create_if_not_exists index(:event_participants, [:user_id, :event_id, :status])
    
    # Index for time-based filtering (upcoming/past events)
    create_if_not_exists index(:events, [:start_at, :deleted_at], where: "deleted_at IS NULL", name: :events_start_at_deleted_at_index)
    
    # Index for archived events query
    create_if_not_exists index(:events, [:deleted_at], where: "deleted_at IS NOT NULL", name: :events_deleted_at_not_null_index)
  end
end