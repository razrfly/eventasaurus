defmodule EventasaurusApp.Repo.Migrations.CreateUserPreferences do
  use Ecto.Migration

  def change do
    create table(:user_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Connection permission levels:
      # - closed: Only user can initiate connections
      # - event_attendees: Only people from shared events can connect (default)
      # - open: Anyone can connect
      add :connection_permission, :string, null: false, default: "event_attendees"

      # Future preferences (reserved for later phases)
      add :show_on_attendee_lists, :boolean, null: false, default: true
      add :discoverable_in_suggestions, :boolean, null: false, default: true

      timestamps()
    end

    # One preferences record per user
    create unique_index(:user_preferences, [:user_id])

    # Index for filtering by permission level (analytics)
    create index(:user_preferences, [:connection_permission])
  end
end
