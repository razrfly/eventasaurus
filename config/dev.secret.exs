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
  pool_size: 10

# Stripe configuration has been moved to config/runtime.exs
# This ensures it's loaded after .env files are processed
