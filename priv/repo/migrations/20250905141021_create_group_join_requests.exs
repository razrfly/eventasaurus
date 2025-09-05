defmodule EventasaurusApp.Repo.Migrations.CreateGroupJoinRequests do
  use Ecto.Migration

  def change do
    create table(:group_join_requests) do
      add :group_id, references(:groups, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, size: 20, default: "pending", null: false
      add :message, :text
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Ensure user can only have one pending request per group
    create unique_index(:group_join_requests, [:group_id, :user_id], 
      where: "status = 'pending'", name: :group_join_requests_unique_pending)
    
    # Performance indexes
    create index(:group_join_requests, [:group_id])
    create index(:group_join_requests, [:user_id])
    create index(:group_join_requests, [:status])
    create index(:group_join_requests, [:reviewed_by_id])
    
    # Ensure valid status values
    create constraint(:group_join_requests, :group_join_requests_status_check,
      check: "status IN ('pending', 'approved', 'denied', 'cancelled')")

    # Enforce review-field invariants:
    # - approved/denied require reviewer and reviewed_at
    # - pending/cancelled must not have reviewer nor reviewed_at
    create constraint(:group_join_requests, :group_join_requests_review_fields_check,
      check: "(status IN ('approved','denied') AND reviewed_by_id IS NOT NULL AND reviewed_at IS NOT NULL)
              OR (status IN ('pending','cancelled') AND reviewed_by_id IS NULL AND reviewed_at IS NULL)")
  end
end
