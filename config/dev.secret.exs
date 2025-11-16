import Config

# Configure the database to use Supabase's PostgreSQL instance
config :eventasaurus, EventasaurusApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 54322,
  database: "postgres",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  # Allow configurable pool size for seeding (default: 10, seeding: 30)
  # Usage: SEED_POOL_SIZE=30 mix seed.dev
  pool_size: String.to_integer(System.get_env("SEED_POOL_SIZE") || "10")

# Stripe configuration has been moved to config/runtime.exs
# This ensures it's loaded after .env files are processed

# Disable PostHog for development to avoid console errors
# To enable PostHog, set POSTHOG_PUBLIC_API_KEY in your .env file
# System.put_env("POSTHOG_PUBLIC_API_KEY", "your_actual_api_key_here")
