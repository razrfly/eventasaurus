# Seed script to configure automated discovery for Kraków
#
# Run with: mix run priv/repo/seeds/discovery_config_krakow.exs

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City
alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
import Ecto.Query
require Logger

Logger.info("🌍 Configuring automated discovery for Kraków...")

# Find Kraków
krakow =
  Repo.one(
    from c in City,
      where: c.slug == "krakow",
      preload: :country
  )

if !krakow do
  Logger.error("❌ Kraków not found in database. Please add it first.")
  System.halt(1)
end

Logger.info("Found Kraków (ID: #{krakow.id})")

# Enable discovery for Kraków
case DiscoveryConfigManager.enable_city(krakow.id) do
  {:ok, city} ->
    Logger.info("✅ Discovery enabled for #{city.name}")

  {:error, reason} ->
    Logger.error("❌ Failed to enable discovery: #{inspect(reason)}")
    System.halt(1)
end

# Configure Bandsintown
Logger.info("Configuring Bandsintown...")

case DiscoveryConfigManager.enable_source(krakow.id, "bandsintown", %{
       "limit" => 100,
       "radius" => 50
     }) do
  {:ok, _} -> Logger.info("  ✅ Bandsintown configured")
  {:error, reason} -> Logger.error("  ❌ Failed: #{inspect(reason)}")
end

# Configure Resident Advisor
Logger.info("Configuring Resident Advisor...")

case DiscoveryConfigManager.enable_source(krakow.id, "resident-advisor", %{
       "limit" => 100,
       "area_id" => 44
     }) do
  {:ok, _} -> Logger.info("  ✅ Resident Advisor configured")
  {:error, reason} -> Logger.error("  ❌ Failed: #{inspect(reason)}")
end

# Configure Karnet (Kraków-specific)
Logger.info("Configuring Karnet...")

case DiscoveryConfigManager.enable_source(krakow.id, "karnet", %{
       "limit" => 100,
       "max_pages" => 10
     }) do
  {:ok, _} -> Logger.info("  ✅ Karnet configured")
  {:error, reason} -> Logger.error("  ❌ Failed: #{inspect(reason)}")
end

# Configure Repertuary (formerly Kino Kraków)
Logger.info("Configuring Repertuary...")

case DiscoveryConfigManager.enable_source(krakow.id, "repertuary", %{
       "days_ahead" => 14,
       "max_pages" => 10
     }) do
  {:ok, _} -> Logger.info("  ✅ Repertuary configured")
  {:error, reason} -> Logger.error("  ❌ Failed: #{inspect(reason)}")
end

# Configure Cinema City
Logger.info("Configuring Cinema City...")

case DiscoveryConfigManager.enable_source(krakow.id, "cinema-city", %{
       "venue_id" => "krakow-bonarka",
       "days_ahead" => 14
     }) do
  {:ok, _} -> Logger.info("  ✅ Cinema City configured")
  {:error, reason} -> Logger.error("  ❌ Failed: #{inspect(reason)}")
end

# Verify configuration
Logger.info("\n📊 Final Configuration:")

krakow = Repo.get!(City, krakow.id)

Logger.info("Discovery enabled: #{krakow.discovery_enabled}")

if krakow.discovery_config do
  Logger.info("Schedule: #{krakow.discovery_config.schedule.cron} (#{krakow.discovery_config.schedule.timezone})")
  Logger.info("Sources configured: #{length(krakow.discovery_config.sources)}")

  Enum.each(krakow.discovery_config.sources, fn source ->
    Logger.info("  → #{source.name}: #{if source.enabled, do: "✅ enabled", else: "❌ disabled"}")
    Logger.info("    Frequency: every #{source.frequency_hours}h")
    Logger.info("    Settings: #{inspect(source.settings)}")
  end)
end

Logger.info("\n✨ Kraków discovery configuration complete!")
Logger.info("The CityDiscoveryOrchestrator will run daily at midnight UTC")
Logger.info("\nTo test immediately (dry run):")
Logger.info("  DRY_RUN=true mix run -e 'EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator.perform(%Oban.Job{})'")
