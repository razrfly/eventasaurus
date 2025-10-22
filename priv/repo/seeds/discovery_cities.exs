# Seed script to configure automated discovery for all cities
#
# This file configures production discovery settings for:
# - Kraków (Poland): 6 sources
# - London (United Kingdom): 2 sources
# - Melbourne (Australia): 2 sources
# - Austin (United States): 1 source
# - Paris (France): 1 source
#
# Run with: mix run priv/repo/seeds/discovery_cities.exs
# Or automatically via: mix ecto.setup

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City
alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
import Ecto.Query
require Logger

Logger.info("🌍 Configuring automated discovery for all cities...")

# Helper function to configure a city with its sources
configure_city = fn city_slug, source_configs ->
  case Repo.one(from c in City, where: c.slug == ^city_slug, preload: :country) do
    nil ->
      Logger.warning("⚠️  City '#{city_slug}' not found, skipping...")
      :not_found

    city ->
      Logger.info("\nConfiguring #{city.name} (#{city.country.name})...")

      # Enable discovery for the city
      result = DiscoveryConfigManager.enable_city(city.id)

      case result do
        {:ok, _} ->
          Logger.info("  ✅ Discovery enabled")

        {:error, reason} ->
          Logger.error("  ❌ Failed to enable discovery: #{inspect(reason)}")
      end

      # Return early if enabling discovery failed
      if elem(result, 0) == :error do
        result
      else

      # Configure each source
      Enum.each(source_configs, fn {source_name, settings} ->
        Logger.info("  Configuring #{source_name}...")

        case DiscoveryConfigManager.enable_source(city.id, source_name, settings) do
          {:ok, _} ->
            Logger.info("    ✅ #{source_name} configured")

          {:error, reason} ->
            Logger.error("    ❌ Failed: #{inspect(reason)}")
        end
      end)

        # Verify final configuration
        city = Repo.get!(City, city.id)

        if city.discovery_config do
          sources = Map.get(city.discovery_config, "sources", [])
          Logger.info("  📊 Final: #{length(sources)} sources configured")
        end

        {:ok, city}
      end
  end
end

# ============================================================================
# KRAKÓW, POLAND - 6 SOURCES
# ============================================================================
# Note: PubQuiz Poland, Karnet, Resident Advisor, Cinema City, Bandsintown, Ticketmaster

configure_city.("krakow", [
  # PubQuiz Poland - Weekly pub quiz events
  {"pubquiz-pl", %{
    "limit" => 100
  }},

  # Karnet - Kraków cultural events portal
  {"karnet", %{
    "limit" => 100,
    "max_pages" => 10
  }},

  # Resident Advisor - Electronic music events
  {"resident-advisor", %{
    "limit" => 1000
  }},

  # Cinema City - Movie showtimes (Bonarka location)
  {"cinema-city", %{
    "limit" => 1000
  }},

  # Bandsintown - Concert discovery
  {"bandsintown", %{
    "limit" => 100,
    "radius" => 50
  }},

  # Ticketmaster - Major concerts, sports, and theater events
  {"ticketmaster", %{
    "limit" => 100,
    "radius" => 50
  }}
])

# ============================================================================
# LONDON, UNITED KINGDOM - 2 SOURCES
# ============================================================================

configure_city.("london", [
  # Question One - Pub quiz events (global source)
  {"question-one", %{
    "limit" => 250
  }},

  # Speed Quizzing - Interactive trivia events (global source)
  {"speed-quizzing", %{
    "limit" => 100
  }}
])

# ============================================================================
# MELBOURNE, AUSTRALIA - 2 SOURCES
# ============================================================================

configure_city.("melbourne", [
  # Quizmeisters - Trivia events (global source via StoreRocket API)
  {"quizmeisters", %{
    "limit" => 100
  }},

  # Question One - Pub quiz events (global source)
  {"question-one", %{
    "limit" => 100
  }}
])

# ============================================================================
# AUSTIN, UNITED STATES - 1 SOURCE
# ============================================================================

configure_city.("austin", [
  # Geeks Who Drink - Trivia events (global source)
  {"geeks-who-drink", %{
    "limit" => 100
  }}
])

# ============================================================================
# PARIS, FRANCE - 1 SOURCE
# ============================================================================

configure_city.("paris", [
  # Sortiraparis - Paris cultural events (concerts, exhibitions, theater)
  {"sortiraparis", %{
    "limit" => 100
  }}
])

# ============================================================================
# SUMMARY
# ============================================================================

Logger.info("\n" <> String.duplicate("=", 60))
Logger.info("✨ Discovery configuration complete!")
Logger.info(String.duplicate("=", 60))

# Load all configured cities
configured_cities =
  Repo.all(
    from c in City,
      where: c.discovery_enabled == true,
      preload: :country,
      order_by: c.name
  )

Logger.info("\n📊 Configured Cities: #{length(configured_cities)}")

Enum.each(configured_cities, fn city ->
  sources = if city.discovery_config, do: Map.get(city.discovery_config, "sources", []), else: []
  source_count = length(sources)
  Logger.info("  → #{city.name}, #{city.country.name}: #{source_count} sources")

  if city.discovery_config do
    Enum.each(sources, fn source ->
      enabled = Map.get(source, "enabled", false)
      name = Map.get(source, "name", "unknown")
      freq = Map.get(source, "frequency_hours", 24)
      status = if enabled, do: "✅", else: "❌"
      Logger.info("      #{status} #{name} (every #{freq}h)")
    end)
  end
end)

Logger.info("\n🤖 Automated Discovery:")
Logger.info("  Schedule: Daily at midnight UTC")
Logger.info("  Orchestrator: EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator")

Logger.info("\n🧪 To test immediately (dry run):")
Logger.info("  DRY_RUN=true mix run -e 'EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator.perform(%Oban.Job{})'")

Logger.info("\n✅ Discovery seeding complete!")
