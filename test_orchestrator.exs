# Quick script to configure Kraków and test orchestrator
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City
alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
alias EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator
import Ecto.Query
require Logger

# Get Kraków
krakow = Repo.one!(from c in City, where: c.slug == "krakow", preload: :country)
Logger.info("Found Kraków: #{krakow.name}")

# Enable discovery
{:ok, _} = DiscoveryConfigManager.enable_city(krakow.id)
Logger.info("✅ Discovery enabled")

# Add Bandsintown
{:ok, _} = DiscoveryConfigManager.enable_source(krakow.id, "bandsintown", %{"limit" => 100, "radius" => 50})
Logger.info("✅ Bandsintown configured")

# Add Karnet
{:ok, _} = DiscoveryConfigManager.enable_source(krakow.id, "karnet", %{"limit" => 100, "max_pages" => 10})
Logger.info("✅ Karnet configured")

# Reload and check
krakow = Repo.get!(City, krakow.id)
Logger.info("Config: #{inspect(krakow.discovery_config)}")

# Test orchestrator
Logger.info("\n🧪 Testing orchestrator in DRY RUN mode...\n")
System.put_env("DRY_RUN", "true")
CityDiscoveryOrchestrator.perform(%Oban.Job{})
