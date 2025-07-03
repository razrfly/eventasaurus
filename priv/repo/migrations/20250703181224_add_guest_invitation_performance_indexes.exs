defmodule EventasaurusApp.Repo.Migrations.AddGuestInvitationPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Index for events.start_at to optimize recency calculations and date-based aggregations
    # Used in: max(e.start_at) aggregations in historical participant queries
    create index(:events, [:start_at], comment: "Optimize date-based aggregations for participant suggestions")

    # Composite index for event_users organizer filtering with event ordering
    # Used in: WHERE eu.user_id = organizer_id ORDER BY e.start_at
    create index(:event_users, [:user_id, :event_id], comment: "Optimize organizer event filtering")

    # NOTE: [:event_id, :user_id] index already exists as unique_index from table creation
    # Composite index for reverse lookup: finding all events a user has participated in
    # Used in: WHERE ep.user_id = ? type queries
    create index(:event_participants, [:user_id, :event_id], comment: "Optimize user-event reverse lookups")

    # Index for event_participants.status to optimize filtering by invitation status
    # Used in: WHERE ep.status = 'pending' type queries
    create index(:event_participants, [:status], comment: "Optimize participant status filtering")

    # Composite index for invitation source tracking queries
    # Used in: filtering participants by who invited them
    create index(:event_participants, [:invited_by_user_id, :event_id], comment: "Optimize invitation source queries")

    # NOTE: [:status] index already exists from enhance_event_state_management migration
    # Composite index for date-based event filtering with status
    # Used in: filtering events by status and date ranges
    create index(:events, [:status, :start_at], comment: "Optimize status + date filtering for events")
  end
end
