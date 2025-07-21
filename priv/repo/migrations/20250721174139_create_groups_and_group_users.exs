defmodule EventasaurusApp.Repo.Migrations.CreateGroupsAndGroupUsers do
  use Ecto.Migration

  def change do
    # Create groups table
    create table(:groups) do
      add :name, :string, null: false, size: 255
      add :slug, :string, null: false, size: 255
      add :description, :text
      add :cover_image_url, :string, size: 255
      add :avatar_url, :string, size: 255
      add :venue_id, references(:venues, on_delete: :nilify_all)
      add :created_by_id, references(:users, on_delete: :restrict), null: false
      
      # Soft delete fields
      add :deleted_at, :utc_datetime
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
      add :deletion_reason, :string
      
      timestamps(type: :utc_datetime)
    end

    # Create unique index on slug
    create unique_index(:groups, :slug)
    create index(:groups, :created_by_id)
    create index(:groups, :venue_id)
    create index(:groups, :deleted_at)

    # Create group_users join table
    create table(:group_users) do
      add :group_id, references(:groups, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, size: 255
      
      # Soft delete fields
      add :deleted_at, :utc_datetime
      add :deleted_by_user_id, references(:users, on_delete: :nilify_all)
      add :deletion_reason, :string
      
      timestamps(type: :utc_datetime)
    end

    # Create indexes on group_users
    create index(:group_users, :group_id)
    create index(:group_users, :user_id)
    create unique_index(:group_users, [:group_id, :user_id])
    create index(:group_users, :deleted_at)

    # Add group_id to events table
    alter table(:events) do
      add :group_id, references(:groups, on_delete: :nilify_all)
    end

    create index(:events, :group_id)
  end
end
