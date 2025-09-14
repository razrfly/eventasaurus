defmodule EventasaurusApp.Repo.Migrations.MigrateVenueCities do
  use Ecto.Migration
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusApp.Venues.Venue
  import Ecto.Query
  require Logger

  def up do
    # This migration handles venues that have city/country strings but no city_id
    # Most venues already have city_id from the scraping system

    Logger.info("Starting venue city migration...")

    # Find venues with city/country strings but no city_id
    venues_to_migrate = from(v in Venue,
      where: not is_nil(v.city) and not is_nil(v.country) and is_nil(v.city_id),
      select: %{id: v.id, city: v.city, country: v.country, state: v.state}
    )
    |> Repo.all()

    Logger.info("Found #{length(venues_to_migrate)} venues to migrate")

    Enum.each(venues_to_migrate, fn venue ->
      migrate_venue_city(venue)
    end)

    Logger.info("Venue city migration completed")
  end

  def down do
    # This is a data migration - we don't reverse it
    # The city_id values will remain, which is fine
    Logger.info("Venue city migration rollback - no action needed")
  end

  defp migrate_venue_city(%{id: venue_id, city: city_name, country: country_name, state: state}) do
    Logger.info("Migrating venue #{venue_id}: #{city_name}, #{state}, #{country_name}")

    try do
      # Step 1: Find or create the country
      country = find_or_create_country(country_name)

      # Step 2: Find or create the city
      city = find_or_create_city(city_name, country)

      # Step 3: Update the venue with city_id
      from(v in Venue, where: v.id == ^venue_id)
      |> Repo.update_all(set: [city_id: city.id, updated_at: DateTime.utc_now()])

      Logger.info("✅ Updated venue #{venue_id} with city_id #{city.id}")

    rescue
      e ->
        Logger.error("❌ Failed to migrate venue #{venue_id}: #{Exception.message(e)}")
        # Continue with other venues even if one fails
    end
  end

  defp find_or_create_country(country_name) do
    # Use Countries library to get proper country data
    country_data = find_country_data(country_name)

    if country_data do
      # Try to find existing country first
      country = Repo.get_by(Country, code: country_data.alpha2) ||
                Repo.get_by(Country, name: country_data.name)

      if country do
        country
      else
        # Create new country with proper data
        %Country{}
        |> Country.changeset(%{
          name: country_data.name,
          code: country_data.alpha2
        })
        |> Repo.insert!()
      end
    else
      Logger.error("Unknown country in migration: #{country_name}")
      # Create with placeholder data if country not found
      %Country{}
      |> Country.changeset(%{
        name: country_name || "Unknown",
        code: "XX"
      })
      |> Repo.insert!()
    end
  end

  defp find_country_data(country_input) when is_binary(country_input) do
    input = String.trim(country_input)

    # Try multiple strategies to find the country
    # 1. Try as country code
    country = if String.length(input) <= 3 do
      Countries.get(String.upcase(input))
    end

    # 2. Try by exact name
    country = country || case Countries.filter_by(:name, input) do
      [c | _] -> c
      _ -> nil
    end

    # 3. Try by unofficial names
    country = country || case Countries.filter_by(:unofficial_names, input) do
      [c | _] -> c
      _ -> nil
    end

    country
  end

  defp find_or_create_city(city_name, country) do
    normalized_name = String.trim(city_name)

    # Try to find existing city in the same country
    city = from(c in City,
      where: c.name == ^normalized_name and c.country_id == ^country.id
    ) |> Repo.one()

    if city do
      city
    else
      # Create new city
      slug = normalized_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s]/, "")
      |> String.replace(~r/\s+/, "-")

      %City{}
      |> City.changeset(%{
        name: normalized_name,
        slug: slug,
        country_id: country.id
      })
      |> Repo.insert!()
    end
  end

end