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
alias EventasaurusApp.Auth.ServiceRoleHelper

# Create Holden's personal login using the comprehensive user manager
IO.puts("🌱 Setting up essential users...")

holden_attrs = %{
  email: "holden@gmail.com",
  name: "Holden",
  username: "holden",
  profile_public: true,
  password: "sawyer1234"
}

case SeedUserManager.get_or_create_user(holden_attrs) do
  {:ok, user} ->
    IO.puts("✅ User ready: #{user.email}")
    
    # Validate authentication if we have the service role key
    if ServiceRoleHelper.service_role_key_available?() do
      case SeedUserManager.validate_auth("holden@gmail.com", "sawyer1234") do
        :ok -> IO.puts("✅ Authentication verified for holden@gmail.com")
        {:error, _} -> IO.puts("⚠️  Authentication not working yet for holden@gmail.com")
      end
    end
    
  {:error, reason} ->
    IO.puts("❌ Failed to create user: #{inspect(reason)}")
    
    # Show instructions if no service role key
    unless ServiceRoleHelper.service_role_key_available?() do
      ServiceRoleHelper.ensure_available()
    end
end

# Seed locations (countries and cities)
IO.puts("\n🌱 Seeding locations...")
Code.eval_file("priv/repo/seeds/locations.exs")

# Seed categories for public events
IO.puts("\n🌱 Seeding categories...")
Code.eval_file("priv/repo/seeds/categories.exs")

# Seed sources for event scraping
IO.puts("\n🌱 Seeding sources...")
Code.eval_file("priv/repo/seeds/sources.exs")

# Seed automated discovery configuration for cities
IO.puts("\n🌱 Seeding discovery configuration...")
Code.eval_file("priv/repo/seeds/discovery_cities.exs")

IO.puts("\n🌱 Seeds completed!")