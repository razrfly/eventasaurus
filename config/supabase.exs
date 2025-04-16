import Config

# Supabase configuration
config :eventasaurus, :supabase,
  url: System.get_env("SUPABASE_URL") || "https://tgbvtzyjzdyquoxnbybt.supabase.co",
  api_key: System.get_env("SUPABASE_API_KEY") || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnYnZ0enlqemR5cXVveG5ieWJ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDQ3MzE2NzgsImV4cCI6MjA2MDMwNzY3OH0.E0CMeRixWQy6DNP0Zb9WTuM8rlHYMZkXPjCqm06LiJc",
  database_url: System.get_env("SUPABASE_DATABASE_URL") || "postgresql://postgres:XzgrUD6rpS!q8&dF42nv@db.tgbvtzyjzdyquoxnbybt.supabase.co:5432/postgres",
  auth: %{
    site_url: "http://localhost:4000",
    additional_redirect_urls: ["https://localhost:4000/auth/callback"],
    auto_confirm_email: true
  }
