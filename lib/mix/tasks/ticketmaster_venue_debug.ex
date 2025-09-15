defmodule Mix.Tasks.Ticketmaster.VenueDebug do
  @moduledoc """
  Debug venue processing for Ticketmaster events.
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer
  import Ecto.Query

  @shortdoc "Debug venue processing for Ticketmaster"

  def run(_args) do
    Application.ensure_all_started(:eventasaurus)

    # Sample venue data from Ticketmaster
    venue_data = %{
      name: "Tauron Arena Kraków",
      city: "Kraków",
      state: "Lesser Poland",
      country: "Poland",
      address: "Stanisława Lema 7",
      latitude: 50.0670,
      longitude: 19.9910
    }

    Logger.info("Testing venue processing with: #{inspect(venue_data, pretty: true)}")

    # Step 1: Process country
    country_name = venue_data[:country] || venue_data["country"]
    Logger.info("\n1. Processing country: #{country_name}")

    country_slug = Normalizer.create_slug(country_name)
    Logger.info("   Country slug: #{country_slug}")

    # Check if country exists
    existing_country = Repo.get_by(Country, slug: country_slug)

    if existing_country do
      Logger.info("   ✅ Country exists: ID=#{existing_country.id}, Code=#{existing_country.code}")
    else
      Logger.info("   ❌ Country doesn't exist, would create new one")
    end

    # Step 2: Process city
    city_name = venue_data[:city] || venue_data["city"]
    Logger.info("\n2. Processing city: #{city_name}")

    city_slug = Normalizer.create_slug(city_name)
    Logger.info("   City slug: #{city_slug}")

    if existing_country do
      # Check if city exists
      existing_city = from(c in City,
        where: c.name == ^city_name and c.country_id == ^existing_country.id,
        limit: 1
      )
      |> Repo.one()

      if existing_city do
        Logger.info("   ✅ City exists: ID=#{existing_city.id}")
      else
        Logger.info("   ❌ City doesn't exist for this country")

        # Check if there's a city with same slug
        city_with_slug = from(c in City,
          where: c.slug == ^city_slug and c.country_id == ^existing_country.id,
          limit: 1
        )
        |> Repo.one()

        if city_with_slug do
          Logger.error("   ⚠️ CONFLICT: City with slug '#{city_slug}' already exists!")
          Logger.error("   Existing: name='#{city_with_slug.name}', id=#{city_with_slug.id}")
        else
          # Try to create city
          Logger.info("   Attempting to create city...")

          changeset = %City{}
          |> City.changeset(%{
            name: city_name,
            country_id: existing_country.id,
            latitude: venue_data[:latitude],
            longitude: venue_data[:longitude]
          })

          if changeset.valid? do
            Logger.info("   Changeset is valid")

            case Repo.insert(changeset) do
              {:ok, city} ->
                Logger.info("   ✅ City created: ID=#{city.id}")
              {:error, changeset} ->
                Logger.error("   ❌ Failed to create city:")
                Enum.each(changeset.errors, fn {field, {msg, _}} ->
                  Logger.error("      #{field}: #{msg}")
                end)
            end
          else
            Logger.error("   ❌ Changeset is invalid:")
            Enum.each(changeset.errors, fn {field, {msg, _}} ->
              Logger.error("      #{field}: #{msg}")
            end)
          end
        end
      end
    end

    # Step 3: Check database for existing cities
    Logger.info("\n3. Checking all cities in Poland:")

    if existing_country do
      cities = from(c in City,
        where: c.country_id == ^existing_country.id,
        order_by: c.name
      )
      |> Repo.all()

      Enum.each(cities, fn city ->
        Logger.info("   - #{city.name} (slug: #{city.slug})")
      end)
    end
  end
end