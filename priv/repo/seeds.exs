# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     EventasaurusApp.Repo.insert!(%EventasaurusApp.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias EventasaurusApp.Auth.SeedUserManager

# Create Holden's personal login using the comprehensive user manager
IO.puts("🌱 Setting up essential users...")

holden_attrs = %{
  email: "holden.thomas@gmail.com",
  name: "Holden",
  username: "holden",
  profile_public: true
}

case SeedUserManager.get_or_create_user(holden_attrs) do
  {:ok, user} ->
    IO.puts("✅ User ready: #{user.email}")
    # Note: Authentication is now handled by Clerk, not Supabase
    # Users authenticate via Clerk OAuth flow, not password-based auth

  {:error, reason} ->
    IO.puts("❌ Failed to create user: #{inspect(reason)}")
end

# Seed locations (countries and cities)
IO.puts("\n🌱 Seeding locations...")
Code.eval_file("priv/repo/seeds/reference_data/locations.exs")

# Seed categories for public events
IO.puts("\n🌱 Seeding categories...")
Code.eval_file("priv/repo/seeds/reference_data/categories.exs")

# Seed sources for event scraping
IO.puts("\n🌱 Seeding sources...")
Code.eval_file("priv/repo/seeds/reference_data/sources.exs")

# Seed automated discovery configuration for cities
IO.puts("\n🌱 Seeding discovery configuration...")
Code.eval_file("priv/repo/seeds/reference_data/discovery_cities.exs")

# Seed test users with different privacy permission levels
IO.puts("\n🌱 Seeding test users with privacy settings...")
Code.eval_file("priv/repo/seeds/test_users_with_preferences.exs")

# Seed test relationships for extended network testing
IO.puts("\n🌱 Seeding test relationships...")
Code.eval_file("priv/repo/seeds/test_relationships.exs")

IO.puts("\n🌱 Seeds completed!")