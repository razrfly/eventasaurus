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
# Increase pool size to handle parallel tests efficiently
pool_size = max(20, System.schedulers_online() * 4)

config :eventasaurus, EventasaurusApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  port: 54322,
  database: "postgres_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: pool_size,
  # Reduce connection timeouts for faster test execution
  timeout: 15_000,
  pool_timeout: 5_000,
  # Longer for complex tests
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

# Test Supabase configuration with local demo values
config :eventasaurus, :supabase,
  url: "http://127.0.0.1:54321",
  api_key:
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
  database_url: "ecto://postgres:postgres@127.0.0.1:54322/postgres_test",
  auth: %{
    site_url: "http://localhost:4002",
    additional_redirect_urls: ["http://localhost:4002/auth/callback"],
    auto_confirm_email: true
  }

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
    # Kino Krakow - Daily scraping due to data quality issues
    "kino-krakow" => 24,
    # Cinema City - Every 2 days (movie showtimes change frequently)
    "cinema-city" => 48
  }
