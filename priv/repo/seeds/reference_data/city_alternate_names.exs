alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.{City, Country}
import Ecto.Query
require Logger

# Seed script to add alternate names to major cities
# This helps prevent duplicate cities when event sources return different language variations

# Map of city alternates: {canonical_name, country_code} => [alternates]
alternate_names_map = %{
  # Poland
  {"Warsaw", "PL"} => ["Warszawa", "Warschau"],
  {"Kraków", "PL"} => ["Krakow", "Krakau", "Cracow"],
  {"Wrocław", "PL"} => ["Wroclaw", "Breslau"],
  {"Gdańsk", "PL"} => ["Gdansk", "Danzig"],
  {"Poznań", "PL"} => ["Poznan", "Posen"],

  # Germany
  {"Munich", "DE"} => ["München", "Munchen"],
  {"Cologne", "DE"} => ["Köln", "Koln"],
  {"Nuremberg", "DE"} => ["Nürnberg", "Nurnberg"],

  # Czech Republic
  {"Prague", "CZ"} => ["Praha"],

  # Austria
  {"Vienna", "AT"} => ["Wien"],

  # France
  {"Paris", "FR"} => ["Parigi", "París"],
  {"Marseille", "FR"} => ["Marsella", "Marsiglia"],

  # Spain
  {"Barcelona", "ES"} => ["Barcelone"],
  {"Seville", "ES"} => ["Sevilla", "Siviglia"],

  # Italy
  {"Rome", "IT"} => ["Roma"],
  {"Milan", "IT"} => ["Milano"],
  {"Venice", "IT"} => ["Venezia", "Venedig"],
  {"Florence", "IT"} => ["Firenze"],
  {"Naples", "IT"} => ["Napoli"],

  # Netherlands
  {"The Hague", "NL"} => ["Den Haag", "'s-Gravenhage"],

  # Belgium
  {"Brussels", "BE"} => ["Bruxelles", "Brussel"],
  {"Antwerp", "BE"} => ["Antwerpen", "Anvers"],

  # Switzerland
  {"Geneva", "CH"} => ["Genève", "Genf", "Ginevra"],
  {"Zurich", "CH"} => ["Zürich"],

  # United Kingdom
  {"London", "GB"} => ["Londra", "Londres"],
  {"Edinburgh", "GB"} => ["Edimburgo"],

  # United States
  {"New York", "US"} => ["Nueva York", "New York City", "NYC"],
  {"Los Angeles", "US"} => ["L.A.", "LA"],
  {"San Francisco", "US"} => ["SF"],

  # Canada
  {"Montreal", "CA"} => ["Montréal"],
  {"Quebec City", "CA"} => ["Québec", "Quebec"],

  # Other European capitals
  {"Copenhagen", "DK"} => ["København"],
  {"Stockholm", "SE"} => ["Estocolmo"],
  {"Oslo", "NO"} => [],
  {"Helsinki", "FI"} => ["Helsingfors"],
  {"Lisbon", "PT"} => ["Lisboa"],
  {"Athens", "GR"} => ["Athina", "Αθήνα"],
  {"Budapest", "HU"} => [],
  {"Bucharest", "RO"} => ["București", "Bukarest"]
}

Logger.info("Adding alternate names to major cities...")

Enum.each(alternate_names_map, fn {{city_name, country_code}, alternates} ->
  # Find the country
  country = Repo.get_by(Country, code: country_code)

  if country do
    # Find the city
    city = Repo.one(
      from c in City,
        where: c.name == ^city_name and c.country_id == ^country.id,
        limit: 1
    )

    if city do
      # Only update if alternates list is not empty
      if length(alternates) > 0 do
        case city
             |> City.changeset(%{alternate_names: alternates})
             |> Repo.update() do
          {:ok, _updated_city} ->
            Logger.info("✓ Added #{length(alternates)} alternate(s) for #{city_name}, #{country_code}: #{Enum.join(alternates, ", ")}")

          {:error, changeset} ->
            Logger.error("✗ Failed to update #{city_name}, #{country_code}: #{inspect(changeset.errors)}")
        end
      else
        Logger.debug("⊘ No alternates to add for #{city_name}, #{country_code}")
      end
    else
      Logger.warning("⚠ City not found: #{city_name}, #{country_code} (will be created when events are imported)")
    end
  else
    Logger.error("✗ Country not found: #{country_code}")
  end
end)

Logger.info("Finished adding alternate names to cities")
