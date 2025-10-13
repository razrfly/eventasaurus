import Config

# Supabase configuration - using environment variables only
# Note: System.fetch_env! validation happens in runtime.exs for production

config :eventasaurus, :supabase,
  url: System.get_env("SUPABASE_URL", "http://127.0.0.1:54321"),
  api_key: System.get_env("SUPABASE_PUBLISHABLE_KEY"),
  service_role_key: System.get_env("SUPABASE_SECRET_KEY"),
  database_url:
    System.get_env("SUPABASE_DATABASE_URL", "ecto://postgres:postgres@127.0.0.1:54322/postgres"),
  auth: %{
    site_url: System.get_env("SUPABASE_SITE_URL", "https://wombie.com"),
    additional_redirect_urls: [
      System.get_env("SUPABASE_SITE_URL", "https://wombie.com") <> "/auth/callback"
    ],
    auto_confirm_email: false
  }
