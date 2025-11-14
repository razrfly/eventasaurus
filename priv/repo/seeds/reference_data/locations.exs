# ============================================================================
# PRODUCTION SEED: Locations (Countries & Cities)
# ============================================================================
#
# Purpose:
#   Seeds core countries and cities with coordinates for event locations.
#   This is reference data needed for event discovery and location matching.
#
# When to run:
#   - During initial setup (mix ecto.setup)
#   - When adding new cities for scraper coverage
#   - After database reset (mix ecto.reset)
#
# Dependencies:
#   - None (can run independently)
#
# Idempotency:
#   - YES: Uses upsert pattern with conflict resolution
#   - Safe to run multiple times
#
# Data created:
#   - Countries: Poland, United Kingdom, United States, Australia, France
#   - Cities: Kraków, Warsaw, London, Austin, Melbourne, Paris
#   - Includes: Name, slug, coordinates, timezone
#
# Usage:
#   mix run priv/repo/seeds/reference_data/locations.exs
#   # Or via main seeds: mix run priv/repo/seeds.exs
#
# ============================================================================

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.{Country, City}

IO.puts("🌍 Seeding countries and cities...")

# First, ensure we have Poland as a country
poland = case Repo.get_by(Country, code: "PL") do
  nil ->
    %Country{}
    |> Country.changeset(%{
      name: "Poland",
      code: "PL",
      slug: "poland"
    })
    |> Repo.insert!()
    |> tap(fn _ -> IO.puts("  ✅ Created country: Poland") end)

  existing ->
    IO.puts("  ℹ️  Country already exists: Poland")
    existing
end

# Ensure we have United Kingdom as a country
uk = case Repo.get_by(Country, code: "GB") do
  nil ->
    %Country{}
    |> Country.changeset(%{
      name: "United Kingdom",
      code: "GB",
      slug: "united-kingdom"
    })
    |> Repo.insert!()
    |> tap(fn _ -> IO.puts("  ✅ Created country: United Kingdom") end)

  existing ->
    IO.puts("  ℹ️  Country already exists: United Kingdom")
    existing
end

# Ensure we have Australia as a country
australia = case Repo.get_by(Country, code: "AU") do
  nil ->
    %Country{}
    |> Country.changeset(%{
      name: "Australia",
      code: "AU",
      slug: "australia"
    })
    |> Repo.insert!()
    |> tap(fn _ -> IO.puts("  ✅ Created country: Australia") end)

  existing ->
    IO.puts("  ℹ️  Country already exists: Australia")
    existing
end

# Ensure we have United States as a country
us = case Repo.get_by(Country, code: "US") do
  nil ->
    %Country{}
    |> Country.changeset(%{
      name: "United States of America",
      code: "US",
      slug: "united-states"
    })
    |> Repo.insert!()
    |> tap(fn _ -> IO.puts("  ✅ Created country: United States of America") end)

  existing ->
    IO.puts("  ℹ️  Country already exists: United States of America")
    existing
end

# Ensure we have France as a country
france = case Repo.get_by(Country, code: "FR") do
  nil ->
    %Country{}
    |> Country.changeset(%{
      name: "France",
      code: "FR",
      slug: "france"
    })
    |> Repo.insert!()
    |> tap(fn _ -> IO.puts("  ✅ Created country: France") end)

  existing ->
    IO.puts("  ℹ️  Country already exists: France")
    existing
end

# Define cities with their coordinates
cities_data = [
  # United Kingdom
  %{
    name: "London",
    slug: "london",
    latitude: 51.5074,
    longitude: -0.1278,
    country_id: uk.id
  },
  # Australia
  %{
    name: "Melbourne",
    slug: "melbourne",
    latitude: -37.8174,
    longitude: 144.9676,
    country_id: australia.id
  },
  # United States
  %{
    name: "Austin",
    slug: "austin",
    latitude: 30.1356,
    longitude: -97.6366,
    country_id: us.id
  },
  # France
  %{
    name: "Paris",
    slug: "paris",
    latitude: 48.8566,
    longitude: 2.3522,
    country_id: france.id
  },
  # Poland
  %{
    name: "Kraków",
    slug: "krakow",
    latitude: 50.0647,
    longitude: 19.9450,
    country_id: poland.id
  },
  %{
    name: "Warsaw",
    slug: "warsaw",
    latitude: 52.2297,
    longitude: 21.0122,
    country_id: poland.id
  },
  %{
    name: "Katowice",
    slug: "katowice",
    latitude: 50.2649,
    longitude: 19.0238,
    country_id: poland.id
  },
  %{
    name: "Gdańsk",
    slug: "gdansk",
    latitude: 54.3520,
    longitude: 18.6466,
    country_id: poland.id
  },
  %{
    name: "Wrocław",
    slug: "wroclaw",
    latitude: 51.1079,
    longitude: 17.0385,
    country_id: poland.id
  },
  %{
    name: "Poznań",
    slug: "poznan",
    latitude: 52.4064,
    longitude: 16.9252,
    country_id: poland.id
  },
  %{
    name: "Łódź",
    slug: "lodz",
    latitude: 51.7592,
    longitude: 19.4560,
    country_id: poland.id
  },
  %{
    name: "Bydgoszcz",
    slug: "bydgoszcz",
    latitude: 53.1235,
    longitude: 18.0084,
    country_id: poland.id
  }
]

# Insert or update cities
for city_data <- cities_data do
  case Repo.get_by(City, slug: city_data.slug, country_id: city_data.country_id) do
    nil ->
      %City{}
      |> City.changeset(city_data)
      |> Repo.insert!()
      IO.puts("  ✅ Created city: #{city_data.name} (#{city_data.latitude}, #{city_data.longitude})")

    existing ->
      # Update coordinates if they're missing or different
      if is_nil(existing.latitude) || is_nil(existing.longitude) ||
         Decimal.to_float(existing.latitude) != city_data.latitude ||
         Decimal.to_float(existing.longitude) != city_data.longitude do

        existing
        |> City.changeset(city_data)
        |> Repo.update!()
        IO.puts("  🔄 Updated city coordinates: #{city_data.name} (#{city_data.latitude}, #{city_data.longitude})")
      else
        IO.puts("  ℹ️  City already exists with coordinates: #{city_data.name}")
      end
  end
end

IO.puts("✅ Location seeding complete!")

# Display summary
cities = Repo.all(City) |> Repo.preload(:country)
IO.puts("\n📍 Cities in database:")
for city <- cities do
  coords = if city.latitude && city.longitude do
    "(#{Decimal.to_float(city.latitude)}, #{Decimal.to_float(city.longitude)})"
  else
    "(no coordinates)"
  end
  IO.puts("  - #{city.name}, #{city.country.name} #{coords}")
end