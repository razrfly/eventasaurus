defmodule EventasaurusApp.Repo.Migrations.AddPendingStatusToUserRelationships do
  use Ecto.Migration

  def change do
    # Status is stored as varchar, so no enum changes needed
    # The Ecto.Enum in the schema handles validation

    # Add request_message for connection request context
    alter table(:user_relationships) do
      add :request_message, :text
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime
    end

    # Index for finding pending requests efficiently
    create index(:user_relationships, [:related_user_id, :status],
             where: "status = 'pending'",
             name: :user_relationships_pending_requests_index)

    # Update the check constraint to allow pending and denied without context
    # Drop the old constraint first
    execute(
      "ALTER TABLE user_relationships DROP CONSTRAINT IF EXISTS context_required_when_active",
      "ALTER TABLE user_relationships ADD CONSTRAINT context_required_when_active CHECK (status <> 'active' OR context IS NOT NULL)"
    )

    # Re-add with same logic (active requires context, others don't)
    execute(
      "ALTER TABLE user_relationships ADD CONSTRAINT context_required_when_active CHECK (status <> 'active' OR context IS NOT NULL)",
      "SELECT 1"
    )
  end
end
