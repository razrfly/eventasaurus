defmodule EventasaurusApp.Repo.Migrations.AddSoftDeleteColumns do
  use Ecto.Migration
  import Ecto.SoftDelete.Migration

  def change do
    # Add soft delete columns to events table
    alter table(:events) do
      soft_delete_columns()
    end

    # Add soft delete columns to related tables that should support cascade soft deletion
    alter table(:tickets) do
      soft_delete_columns()
    end

    alter table(:orders) do
      soft_delete_columns()
    end

    alter table(:polls) do
      soft_delete_columns()
    end

    alter table(:poll_options) do
      soft_delete_columns()
    end

    alter table(:poll_votes) do
      soft_delete_columns()
    end

    alter table(:event_participants) do
      soft_delete_columns()
    end

    alter table(:event_users) do
      soft_delete_columns()
    end

    # Create indexes for better query performance
    create index(:events, [:deleted_at])
    create index(:tickets, [:deleted_at])
    create index(:orders, [:deleted_at])
    create index(:polls, [:deleted_at])
    create index(:poll_options, [:deleted_at])
    create index(:poll_votes, [:deleted_at])
    create index(:event_participants, [:deleted_at])
    create index(:event_users, [:deleted_at])
  end
end
