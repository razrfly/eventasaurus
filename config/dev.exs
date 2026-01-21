import Config

# Set environment
config :eventasaurus, :environment, :dev

# =============================================================================
# Database Configuration Toggle
# =============================================================================
# Set USE_PROD_DB=true to connect to production Fly Managed Postgres
# Default: local PostgreSQL (safe for development)
#
# Usage:
#   Normal dev:     mix phx.server
#   With prod DB:   USE_PROD_DB=true mix phx.server
#                   (or add USE_PROD_DB=true to .env temporarily)
#
# Prerequisites for USE_PROD_DB:
#   1. Set DATABASE_URL in .env (get from `fly secrets list -a eventasaurus`)
#   2. Start fly proxy: `fly proxy 5433:5432 -a eventasaurus-db`
#   3. Or use WireGuard VPN: `fly wireguard create`
# =============================================================================

# Load .env file at compile time if it exists (needed for USE_PROD_DB mode)
# This ensures Fly MPG credentials are available before config is evaluated
if File.exists?(".env") do
  File.read!(".env")
  |> String.split("\n")
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)
        # Skip comments and empty lines
        unless String.starts_with?(key, "#") or key == "" do
          System.put_env(key, value)
        end

      _ ->
        :ok
    end
  end)
end

use_prod_db = System.get_env("USE_PROD_DB") == "true"

# Store toggle state for runtime access (e.g., admin dashboard indicator)
config :eventasaurus, :use_prod_db, use_prod_db

if use_prod_db do
  # Print warning to console
  IO.puts("""

  ╔═══════════════════════════════════════════════════════════════════════════╗
  ║  ⚠️  WARNING: CONNECTED TO PRODUCTION DATABASE                             ║
  ║                                                                           ║
  ║  USE_PROD_DB=true is set. All database operations will affect PRODUCTION! ║
  ║  Unset USE_PROD_DB or set to 'false' to use local PostgreSQL.             ║
  ╚═══════════════════════════════════════════════════════════════════════════╝

  """)

  # Fly Managed Postgres production database configuration
  # Uses DATABASE_URL (PgBouncer) and DATABASE_DIRECT_URL (direct connection)
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL not set. Get it from: fly secrets list -a eventasaurus"

  database_direct_url =
    System.get_env("DATABASE_DIRECT_URL") ||
      raise "DATABASE_DIRECT_URL not set. Get it from: fly secrets list -a eventasaurus"

  # Repo: Pooled connection via PgBouncer for web requests
  # Higher pool size for dev since we're the only user and need headroom for LiveView
  config :eventasaurus, EventasaurusApp.Repo,
    url: database_url,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10,
    queue_target: 5000,
    queue_interval: 10000,
    parameters: [
      application_name: "eventasaurus_dev"
    ],
    prepare: :unnamed

  # SessionRepo: Direct connection for migrations and advisory locks
  config :eventasaurus, EventasaurusApp.SessionRepo,
    url: database_direct_url,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 5,
    queue_target: 5000,
    queue_interval: 10000,
    parameters: [
      application_name: "eventasaurus_session_dev"
    ]

  # ReplicaRepo: Pooled connection for read-heavy operations
  config :eventasaurus, EventasaurusApp.ReplicaRepo,
    url: database_url,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10,
    queue_target: 5000,
    queue_interval: 10000,
    parameters: [
      application_name: "eventasaurus_replica_dev"
    ],
    prepare: :unnamed

  # JobRepo: Direct connection for Oban job business logic (Issue #3353)
  # Uses direct URL to bypass PgBouncer timeout for long-running queries
  config :eventasaurus, EventasaurusApp.JobRepo,
    url: database_direct_url,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 20,
    queue_target: 5000,
    queue_interval: 10000,
    parameters: [
      application_name: "eventasaurus_job_dev"
    ]

  # ObanRepo: DEPRECATED - kept for backwards compatibility (Issue #3353)
  config :eventasaurus, EventasaurusApp.ObanRepo,
    url: database_url,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 5,
    queue_target: 5000,
    queue_interval: 10000,
    parameters: [
      application_name: "eventasaurus_oban_dev"
    ],
    prepare: :unnamed
else
  # Default: Local PostgreSQL for development
  config :eventasaurus, EventasaurusApp.Repo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "eventasaurus_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10

  # SessionRepo for development (migrations and advisory locks)
  config :eventasaurus, EventasaurusApp.SessionRepo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "eventasaurus_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 2

  # ReplicaRepo for development (points to same DB)
  config :eventasaurus, EventasaurusApp.ReplicaRepo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "eventasaurus_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 5

  # JobRepo for development - direct connection for job business logic (Issue #3353)
  config :eventasaurus, EventasaurusApp.JobRepo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "eventasaurus_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 20

  # ObanRepo for development - DEPRECATED (Issue #3353)
  config :eventasaurus, EventasaurusApp.ObanRepo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "eventasaurus_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 5
end

# Development-only features
config :eventasaurus, :dev_quick_login, true
# Debug staged loading - adds artificial delays to visualize loading stages
# Set to `true` temporarily to test loading skeletons/animations
# 500ms delay on initial data + 2000ms delay on events loading
config :eventasaurus, :debug_staged_loading, false
# Enable week.pl source in full phase (all 13 Polish cities)
config :eventasaurus, :week_pl_deployment_phase, :full

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
# Binding to loopback ipv4 address prevents access from other machines.

# Configure PostHog settings for development
# PostHog provides analytics and event tracking for your application
# To enable PostHog, set the following environment variables:
# - POSTHOG_PUBLIC_API_KEY: Your PostHog project API key (for event tracking)
# - POSTHOG_PRIVATE_API_KEY: Your PostHog personal API key (for analytics queries)
# - POSTHOG_PROJECT_ID: Your PostHog project ID (for analytics queries)
#
# Get these from your PostHog dashboard:
# 1. Project API Key: Project Settings > API Keys
# 2. Personal API Key: Personal Settings > Personal API Keys
# 3. Project ID: Project Settings > Project Variables
config :eventasaurus, :posthog,
  api_key: System.get_env("POSTHOG_PUBLIC_API_KEY"),
  api_host: "https://eu.i.posthog.com"

# Configure base URL for email links
config :eventasaurus, :base_url, "http://localhost:4000"

config :eventasaurus, EventasaurusWeb.Endpoint,
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "OW51JE7b0kmI7NHAjS+859KMrYf+jrpHFa9xyMqmlvNYmquOpS83H7Ea7eR59DMA",
  # Explicitly set HTTP adapter to Cowboy
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:eventasaurus, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:eventasaurus, ~w(--watch)]}
  ]

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
#
#     https: [
#       port: 4001,
#       cipher_suite: :strong,
#       keyfile: "priv/cert/selfsigned_key.pem",
#       certfile: "priv/cert/selfsigned.pem"
#     ],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Watch static and templates for browser reloading.
config :eventasaurus, EventasaurusWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/eventasaurus_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :eventasaurus, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include HEEx debug annotations as HTML comments in rendered markup
  debug_heex_annotations: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Configure mailer for development - use local mailbox
config :eventasaurus, Eventasaurus.Mailer, adapter: Swoosh.Adapters.Local

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Event discovery scraper configuration
# Note: Not a separate OTP app, just using config namespace for organization
config :eventasaurus, :event_discovery,
  # Universal event freshness threshold for all scrapers (in hours)
  # Events seen within this window will NOT be re-scraped
  # 7 days
  freshness_threshold_hours: 168,
  # Source-specific freshness threshold overrides
  # Sources not listed here will use the default freshness_threshold_hours
  source_freshness_overrides: %{
    # Repertuary - Daily scraping due to data quality issues
    "repertuary" => 24,
    # Cinema City - Every 2 days (movie showtimes change frequently)
    "cinema-city" => 48
  }

# Cloudflare R2 configuration for development
# Set these environment variables in .env to test R2 uploads locally:
# - CLOUDFLARE_ACCOUNT_ID
# - CLOUDFLARE_ACCESS_KEY_ID
# - CLOUDFLARE_SECRET_ACCESS_KEY
# - R2_BUCKET (optional, defaults to "wombie")
# - R2_CDN_URL (optional, defaults to "https://cdn2.wombie.com")
#
# If not set, R2 uploads will fail with a configuration error.
config :eventasaurus, :r2,
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  access_key_id: System.get_env("CLOUDFLARE_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("CLOUDFLARE_SECRET_ACCESS_KEY"),
  bucket: System.get_env("R2_BUCKET") || "wombie",
  cdn_url: System.get_env("R2_CDN_URL") || "https://cdn2.wombie.com"
