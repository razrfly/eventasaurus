import Config

# Supabase configuration - using environment variables only
config :eventasaurus, :supabase,
  url: System.get_env("SUPABASE_URL"),
  api_key: System.get_env("SUPABASE_API_KEY"),
  database_url: System.get_env("SUPABASE_DATABASE_URL"),
  auth: %{
    site_url: "https://eventasaur.us/"
  }
