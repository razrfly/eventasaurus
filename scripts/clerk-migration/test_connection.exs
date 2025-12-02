#!/usr/bin/env elixir
# Test Clerk API connection
# Usage: CLERK_ENABLED=true mix run scripts/clerk-migration/test_connection.exs

IO.puts("Testing Clerk API connection...")

clerk_config = Application.get_env(:eventasaurus, :clerk, [])
IO.puts("Enabled: #{clerk_config[:enabled]}")
IO.puts("Domain: #{clerk_config[:domain]}")
IO.puts("Secret key present: #{clerk_config[:secret_key] != nil}")

case EventasaurusApp.Auth.Clerk.Client.list_users(limit: 3) do
  {:ok, users} ->
    IO.puts("\n✓ Connected to Clerk successfully!")
    IO.puts("  Found #{length(users)} users (showing max 3)\n")

    Enum.each(users, fn user ->
      email =
        case user["email_addresses"] do
          [first | _] -> first["email_address"]
          _ -> "no email"
        end

      IO.puts("  - #{email}")
      IO.puts("    clerk_id: #{user["id"]}")

      if user["external_id"] do
        IO.puts("    external_id: #{user["external_id"]} (Supabase UUID)")
      end

      IO.puts("")
    end)

  {:error, reason} ->
    IO.puts("\n✗ Failed to connect: #{inspect(reason)}")
end
