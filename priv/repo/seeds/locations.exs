# Seeds for countries and cities with coordinates
# This file sets up test cities for scraper development

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