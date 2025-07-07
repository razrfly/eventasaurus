defmodule EventasaurusApp.Repo.Migrations.AddUserSearchPerformanceIndexes do
  use Ecto.Migration

  def up do
    # Index for efficient ILIKE searches on user names
    # This supports the search_users_for_organizers function that searches by name
    create index(:users, ["lower(name)"], name: :users_name_lower_index,
      comment: "Optimize case-insensitive name searches for user search API")

    # Index for efficient ILIKE searches on user emails
    # While unique_index on email exists, this helps with partial email searches
    create index(:users, ["lower(email)"], name: :users_email_lower_index,
      comment: "Optimize case-insensitive email searches for user search API")

    # Composite index for multi-field searches with privacy filtering
    # This optimizes queries that search across name, username, email with profile_public filter
    create index(:users, [:profile_public, "lower(name)", "lower(username)", "lower(email)"],
      name: :users_search_composite_index,
      comment: "Optimize multi-field user searches with privacy filtering")

    # Index for efficient event organizer exclusion queries
    # This supports the LEFT JOIN in search_users_for_organizers when excluding existing organizers
    create index(:event_users, [:event_id, :user_id], name: :event_users_exclusion_index,
      comment: "Optimize queries that exclude existing event organizers from search results")

    # Conditional index for active user searches (users with public profiles)
    # This optimizes the most common search case where we're looking for users with public profiles
    create index(:users, ["lower(name)", "lower(username)", "lower(email)"],
      name: :users_public_search_index,
      where: "profile_public = true",
      comment: "Optimize searches for users with public profiles")

    # Index for user ID exclusion in searches (commonly used to exclude the searching user)
    # This helps with the WHERE NOT u.id = ? conditions
    create index(:users, [:id, :profile_public], name: :users_id_profile_index,
      comment: "Optimize user exclusion queries in search results")
  end

  def down do
    # Drop indexes in reverse order
    drop index(:users, [:id, :profile_public], name: :users_id_profile_index)
    drop index(:users, ["lower(name)", "lower(username)", "lower(email)"], name: :users_public_search_index)
    drop index(:event_users, [:event_id, :user_id], name: :event_users_exclusion_index)
    drop index(:users, [:profile_public, "lower(name)", "lower(username)", "lower(email)"], name: :users_search_composite_index)
    drop index(:users, ["lower(email)"], name: :users_email_lower_index)
    drop index(:users, ["lower(name)"], name: :users_name_lower_index)
  end
end
