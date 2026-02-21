# Test users with different privacy/connection permission settings
# Run with: mix run priv/repo/seeds/test_users_with_preferences.exs
#
# Creates 5 test users with different connection_permission settings:
# - Alice (open) - Anyone can connect
# - Bob (event_attendees) - Only people from shared events (default)
# - Carol (extended_network) - Friends of friends only
# - Dave (closed) - No one can connect, Dave reaches out first
# - Eve (event_attendees) - Another default user for testing connections

alias EventasaurusApp.Repo
alias EventasaurusApp.Accounts
alias EventasaurusApp.Accounts.User
alias EventasaurusApp.Accounts.UserPreferences

IO.puts("🌱 Creating test users with different privacy settings...")

# Helper to create or update user
defmodule TestUserSeeder do
  def get_or_create_user(attrs) do
    case Repo.get_by(User, email: attrs.email) do
      nil ->
        attrs = Map.put_new_lazy(attrs, :family_name, &EventasaurusApp.Families.random_family_name/0)

        %User{}
        |> User.changeset(attrs)
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def set_preference(user, permission) do
    case Repo.get_by(UserPreferences, user_id: user.id) do
      nil ->
        %UserPreferences{}
        |> UserPreferences.changeset(%{user_id: user.id, connection_permission: permission})
        |> Repo.insert()

      prefs ->
        prefs
        |> UserPreferences.update_changeset(%{connection_permission: permission})
        |> Repo.update()
    end
  end
end

# Define test users
test_users = [
  %{
    email: "alice@example.com",
    name: "Alice Open",
    username: "alice_open",
    profile_public: true,
    clerk_id: "test_alice_001",
    permission: :open
  },
  %{
    email: "bob@example.com",
    name: "Bob EventAttendees",
    username: "bob_events",
    profile_public: true,
    clerk_id: "test_bob_002",
    permission: :event_attendees
  },
  %{
    email: "carol@example.com",
    name: "Carol ExtendedNetwork",
    username: "carol_extended",
    profile_public: true,
    clerk_id: "test_carol_003",
    permission: :extended_network
  },
  %{
    email: "dave@example.com",
    name: "Dave Closed",
    username: "dave_closed",
    profile_public: true,
    clerk_id: "test_dave_004",
    permission: :closed
  },
  %{
    email: "eve@example.com",
    name: "Eve Default",
    username: "eve_default",
    profile_public: true,
    clerk_id: "test_eve_005",
    permission: :event_attendees
  }
]

# Create users and set their preferences
created_users =
  Enum.map(test_users, fn user_data ->
    permission = user_data.permission
    user_attrs = Map.drop(user_data, [:permission])

    case TestUserSeeder.get_or_create_user(user_attrs) do
      {:ok, user} ->
        case TestUserSeeder.set_preference(user, permission) do
          {:ok, _prefs} ->
            IO.puts("  ✅ #{user.name} (#{user.email}) - #{permission}")
            {user, permission}

          {:error, reason} ->
            IO.puts("  ❌ Failed to set preference for #{user.email}: #{inspect(reason)}")
            nil
        end

      {:error, reason} ->
        IO.puts("  ❌ Failed to create #{user_data.email}: #{inspect(reason)}")
        nil
    end
  end)
  |> Enum.reject(&is_nil/1)

IO.puts("\n📊 Summary:")
IO.puts("  Created/updated #{length(created_users)} test users")
IO.puts("")
IO.puts("  Permission levels:")
IO.puts("    - open: Alice can be connected by anyone")
IO.puts("    - event_attendees: Bob & Eve require shared events")
IO.puts("    - extended_network: Carol requires friend-of-friend")
IO.puts("    - closed: Dave must reach out first")
IO.puts("")
IO.puts("🌱 Test users seeded!")
