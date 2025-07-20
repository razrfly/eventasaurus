defmodule EventasaurusApp.Repo.Migrations.AddDeletionMetadataColumns do
  use Ecto.Migration

  def change do
    # Add deletion metadata columns to events table
    alter table(:events) do
      add :deletion_reason, :string
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    # Add deletion metadata columns to related tables
    alter table(:tickets) do
      add :deletion_reason, :string
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:orders) do
      add :deletion_reason, :string
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:polls) do
      add :deletion_reason, :string
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:poll_options) do
      add :deletion_reason, :string
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:poll_votes) do
      add :deletion_reason, :string
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:event_participants) do
      add :deletion_reason, :string
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    alter table(:event_users) do
      add :deletion_reason, :string
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
    end

    # Add indexes for the deleted_by_user_id foreign keys
    create index(:events, [:deleted_by_user_id])
    create index(:tickets, [:deleted_by_user_id])
    create index(:orders, [:deleted_by_user_id])
    create index(:polls, [:deleted_by_user_id])
    create index(:poll_options, [:deleted_by_user_id])
    create index(:poll_votes, [:deleted_by_user_id])
    create index(:event_participants, [:deleted_by_user_id])
    create index(:event_users, [:deleted_by_user_id])
  end
end
