import Config

# Supabase configuration - using environment variables only
# Note: System.fetch_env! validation happens in runtime.exs for production

config :eventasaurus, :supabase,
  url: System.get_env("SUPABASE_URL", "http://127.0.0.1:54321"),
  api_key: System.get_env("SUPABASE_API_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"),
  database_url: System.get_env("SUPABASE_DATABASE_URL", "ecto://postgres:postgres@127.0.0.1:54322/postgres"),
  auth: %{
    site_url: System.get_env("SUPABASE_SITE_URL", "https://eventasaur.us"),
    additional_redirect_urls: [
      System.get_env("SUPABASE_SITE_URL", "https://eventasaur.us") <> "/auth/callback"
    ],
    auto_confirm_email: false
  }
