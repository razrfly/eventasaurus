import Config

# Set environment
config :eventasaurus, :environment, :test

# Development-only features (disabled in test)
config :eventasaurus, :dev_quick_login, false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :eventasaurus, EventasaurusWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Lhh9Ga/AhSUhDIFHhhxkIeO7VTsCs8VRMH+vEZm8ygOO1qyrat2inn/8vdVRxRIm",
  server: true

# Configure the database for testing
# Using local Postgres.app with PostGIS extension
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
#
# IMPORTANT: Fixed pool sizes for tests to avoid connection exhaustion (Issue #3353)
# With 5 repos (Repo, SessionRepo, ReplicaRepo, JobRepo, ObanRepo), we need to stay
# well under PostgreSQL's default 100 connection limit. Total: 10+5+3+5+3 = 26 connections

config :eventasaurus, EventasaurusApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "eventasaurus_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  # Reduce connection timeouts for faster test execution
  timeout: 15_000,
  pool_timeout: 5_000,
  # Longer for complex tests
  ownership_timeout: 60_000

# Configure SessionRepo for testing (migrations, advisory locks)
# In test, both repos point to the same test database
config :eventasaurus, EventasaurusApp.SessionRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "eventasaurus_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  timeout: 15_000,
  pool_timeout: 5_000,
  ownership_timeout: 60_000

# Configure ReplicaRepo for testing
# In test, replica points to same test database for sandbox compatibility
# Note: Repo.replica() returns the primary Repo in test environment,
# so this config is mainly for completeness and edge case testing
config :eventasaurus, EventasaurusApp.ReplicaRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "eventasaurus_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 3,
  timeout: 15_000,
  pool_timeout: 5_000,
  ownership_timeout: 60_000

# Configure JobRepo for testing - direct connection for job business logic (Issue #3353)
# In test, uses same sandbox as other repos for transactional isolation
config :eventasaurus, EventasaurusApp.JobRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "eventasaurus_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  timeout: 15_000,
  pool_timeout: 5_000,
  ownership_timeout: 60_000

# Configure ObanRepo for testing - DEPRECATED (Issue #3353)
# In test, uses same sandbox as other repos for transactional isolation
config :eventasaurus, EventasaurusApp.ObanRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "eventasaurus_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 3,
  timeout: 15_000,
  pool_timeout: 5_000,
  ownership_timeout: 60_000

# In test we don't send emails
config :eventasaurus, Eventasaurus.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Configure base URL for email links in tests
config :eventasaurus, :base_url, "http://localhost:4002"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Test-specific configuration for Auth.Client mocking
config :eventasaurus, :auth_client, EventasaurusApp.Auth.TestClient

# Configure Stripe mock for testing
config :eventasaurus, :stripe_module, EventasaurusApp.StripeMock

# Configure Wallaby for browser automation testing
config :wallaby,
  driver: Wallaby.Chrome,
  chromedriver: [
    headless: System.get_env("CI") == "true",
    # Disable version checking for compatibility
    capabilities: %{
      chromeOptions: %{
        args: [
          "--no-sandbox",
          "--disable-dev-shm-usage",
          "--disable-gpu",
          "--remote-debugging-port=9222"
        ]
      }
    }
  ],
  screenshot_on_failure: true,
  js_errors: false,
  timeout: 30_000,
  base_url: "http://localhost:4002"

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
