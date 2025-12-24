# Test relationships for privacy permission testing
# Run with: mix run priv/repo/seeds/test_relationships.exs
#
# Prerequisites: Run test_users_with_preferences.exs first
#
# Creates relationships to test extended_network permission:
# - Demo User <-> Alice (connected)
# - Alice <-> Bob (connected)
# - Alice <-> Eve (connected)
#
# This means:
# - Demo User is 1 degree from Alice
# - Demo User is 2 degrees from Bob (friend of friend via Alice)
# - Demo User is 2 degrees from Eve (friend of friend via Alice)
# - Demo User is NOT connected to Carol or Dave at any degree

alias EventasaurusApp.Repo
alias EventasaurusApp.Accounts.User
alias EventasaurusApp.Relationships

IO.puts("🌱 Creating test relationships for permission testing...")

# Helper to find user by email
defmodule RelationshipSeeder do
  def find_user(email) do
    Repo.get_by(User, email: email)
  end

  def create_relationship(user1, user2, context) do
    case Relationships.get_relationship_between(user1, user2) do
      nil ->
        case Relationships.create_manual(user1, user2, context) do
          {:ok, {rel, _reverse}} ->
            {:ok, rel}

          error ->
            error
        end

      existing ->
        {:ok, existing}
    end
  end
end

# Find users
demo = RelationshipSeeder.find_user("demo@example.com")
alice = RelationshipSeeder.find_user("alice@example.com")
bob = RelationshipSeeder.find_user("bob@example.com")
eve = RelationshipSeeder.find_user("eve@example.com")

cond do
  is_nil(alice) or is_nil(bob) or is_nil(eve) ->
    IO.puts("❌ Test users not found. Run test_users_with_preferences.exs first.")

  is_nil(demo) ->
    # Demo user not found - create relationships between test users only
    IO.puts("⚠️  Demo user not found. Creating relationships between test users only.")
    IO.puts("    (Log in as demo@example.com first to test the full relationship graph)")

    # Create Alice <-> Bob relationship
    case RelationshipSeeder.create_relationship(alice, bob, "Friends from work") do
      {:ok, _} ->
        IO.puts("  ✅ Alice <-> Bob (connected)")

      {:error, reason} ->
        IO.puts("  ❌ Failed: Alice <-> Bob: #{inspect(reason)}")
    end

    # Create Alice <-> Eve relationship
    case RelationshipSeeder.create_relationship(alice, eve, "College friends") do
      {:ok, _} ->
        IO.puts("  ✅ Alice <-> Eve (connected)")

      {:error, reason} ->
        IO.puts("  ❌ Failed: Alice <-> Eve: #{inspect(reason)}")
    end

    IO.puts("")
    IO.puts("📊 Current relationship graph:")
    IO.puts("  Alice (open)")
    IO.puts("    ├── Bob (event_attendees)")
    IO.puts("    └── Eve (event_attendees)")
    IO.puts("")
    IO.puts("🌱 Test relationships seeded (partial - no demo user)!")

  true ->
    IO.puts("  Found Demo User: #{demo.email}")

    # Create Demo <-> Alice relationship
    case RelationshipSeeder.create_relationship(demo, alice, "Met at seed testing") do
      {:ok, _} ->
        IO.puts("  ✅ Demo User <-> Alice (connected)")

      {:error, reason} ->
        IO.puts("  ❌ Failed: Demo <-> Alice: #{inspect(reason)}")
    end

    # Create Alice <-> Bob relationship
    case RelationshipSeeder.create_relationship(alice, bob, "Friends from work") do
      {:ok, _} ->
        IO.puts("  ✅ Alice <-> Bob (connected)")

      {:error, reason} ->
        IO.puts("  ❌ Failed: Alice <-> Bob: #{inspect(reason)}")
    end

    # Create Alice <-> Eve relationship
    case RelationshipSeeder.create_relationship(alice, eve, "College friends") do
      {:ok, _} ->
        IO.puts("  ✅ Alice <-> Eve (connected)")

      {:error, reason} ->
        IO.puts("  ❌ Failed: Alice <-> Eve: #{inspect(reason)}")
    end

    IO.puts("")
    IO.puts("📊 Relationship graph for Demo User:")
    IO.puts("  Demo User")
    IO.puts("    └── Alice (1 degree) - permission: open")
    IO.puts("          ├── Bob (2 degrees) - permission: event_attendees")
    IO.puts("          └── Eve (2 degrees) - permission: event_attendees")
    IO.puts("")
    IO.puts("  NOT connected:")
    IO.puts("    - Carol (extended_network) - Demo is NOT in Carol's extended network")
    IO.puts("    - Dave (closed) - Dave must reach out first")
    IO.puts("")
    IO.puts("🌱 Test relationships seeded!")
end
