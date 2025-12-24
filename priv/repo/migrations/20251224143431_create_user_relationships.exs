defmodule EventasaurusApp.Repo.Migrations.CreateUserRelationships do
  use Ecto.Migration

  def change do
    create table(:user_relationships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :related_user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"
      add :origin, :string, null: false
      add :context, :string
      add :originated_from_event_id, references(:events, on_delete: :nilify_all)
      add :shared_event_count, :integer, default: 1, null: false
      add :last_shared_event_at, :utc_datetime

      timestamps()
    end

    # Unique constraint: one relationship per user pair
    create unique_index(:user_relationships, [:user_id, :related_user_id])

    # Index for looking up relationships by related user
    create index(:user_relationships, [:related_user_id])

    # Index for filtering by status
    create index(:user_relationships, [:user_id, :status])

    # Index for analytics by origin type
    create index(:user_relationships, [:origin])

    # Index for finding cooling relationships
    create index(:user_relationships, [:last_shared_event_at])

    # Prevent self-relationships
    create constraint(:user_relationships, :no_self_relationship,
             check: "user_id != related_user_id"
           )

    # Context required for active relationships
    create constraint(:user_relationships, :context_required_when_active,
             check: "status != 'active' OR context IS NOT NULL"
           )
  end
end
