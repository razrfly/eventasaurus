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

# Configure Stripe for development
# Set your Stripe secret key as an environment variable: STRIPE_SECRET_KEY
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY") || "sk_test_YOUR_TEST_KEY_HERE",
  connect_client_id: System.get_env("STRIPE_CONNECT_CLIENT_ID") || "ca_YOUR_CONNECT_CLIENT_ID_HERE"
