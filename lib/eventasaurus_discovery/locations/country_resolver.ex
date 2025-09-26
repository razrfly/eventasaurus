defmodule EventasaurusDiscovery.Locations.CountryResolver do
  @moduledoc """
  Resolves country names in various languages to ISO country codes.

  This module helps handle localized country names from various APIs
  that may return country names in different languages (e.g., "Polska" for Poland,
  "Deutschland" for Germany).
  """

  require Logger

  # Common country name translations to ISO codes
  # Covers major European languages and common variations
  @translations %{
    # Poland
    "polska" => "PL",
    "poland" => "PL",
    "pologne" => "PL",
    "polonia" => "PL",
    "polen" => "PL",
    "polsko" => "PL",

    # Germany
    "niemcy" => "DE",
    "deutschland" => "DE",
    "germany" => "DE",
    "allemagne" => "DE",
    "germania" => "DE",
    "alemania" => "DE",
    "německo" => "DE",

    # France
    "francja" => "FR",
    "france" => "FR",
    "frankreich" => "FR",
    "francia" => "FR",
    "francie" => "FR",

    # United Kingdom
    "wielka brytania" => "GB",
    "united kingdom" => "GB",
    "great britain" => "GB",
    "royaume-uni" => "GB",
    "regno unito" => "GB",
    "reino unido" => "GB",
    "großbritannien" => "GB",
    "uk" => "GB",

    # United States
    "stany zjednoczone" => "US",
    "united states" => "US",
    "états-unis" => "US",
    "stati uniti" => "US",
    "estados unidos" => "US",
    "vereinigte staaten" => "US",
    "usa" => "US",

    # Spain
    "hiszpania" => "ES",
    "spain" => "ES",
    "espagne" => "ES",
    "spagna" => "ES",
    "españa" => "ES",
    "spanien" => "ES",
    "španělsko" => "ES",

    # Italy
    "włochy" => "IT",
    "italy" => "IT",
    "italie" => "IT",
    "italia" => "IT",
    "italien" => "IT",
    "itálie" => "IT",

    # Netherlands
    "holandia" => "NL",
    "netherlands" => "NL",
    "pays-bas" => "NL",
    "paesi bassi" => "NL",
    "países bajos" => "NL",
    "niederlande" => "NL",
    "nizozemsko" => "NL",
    "holland" => "NL",

    # Belgium
    "belgia" => "BE",
    "belgium" => "BE",
    "belgique" => "BE",
    "belgio" => "BE",
    "bélgica" => "BE",
    "belgien" => "BE",
    "belgie" => "BE",

    # Austria
    "austria" => "AT",
    "autriche" => "AT",
    "österreich" => "AT",
    "rakousko" => "AT",

    # Switzerland
    "szwajcaria" => "CH",
    "switzerland" => "CH",
    "suisse" => "CH",
    "svizzera" => "CH",
    "suiza" => "CH",
    "schweiz" => "CH",
    "švýcarsko" => "CH",

    # Czech Republic
    "czechy" => "CZ",
    "czech republic" => "CZ",
    "république tchèque" => "CZ",
    "repubblica ceca" => "CZ",
    "república checa" => "CZ",
    "tschechien" => "CZ",
    "česko" => "CZ",
    "česká republika" => "CZ",

    # Slovakia
    "słowacja" => "SK",
    "slovakia" => "SK",
    "slovaquie" => "SK",
    "slovacchia" => "SK",
    "eslovaquia" => "SK",
    "slowakei" => "SK",
    "slovensko" => "SK",

    # Hungary
    "węgry" => "HU",
    "hungary" => "HU",
    "hongrie" => "HU",
    "ungheria" => "HU",
    "hungría" => "HU",
    "ungarn" => "HU",
    "maďarsko" => "HU",
    "magyarország" => "HU",

    # Canada
    "kanada" => "CA",
    "canada" => "CA",

    # Sweden
    "szwecja" => "SE",
    "sweden" => "SE",
    "suède" => "SE",
    "svezia" => "SE",
    "suecia" => "SE",
    "schweden" => "SE",
    "sverige" => "SE",

    # Norway
    "norwegia" => "NO",
    "norway" => "NO",
    "norvège" => "NO",
    "norvegia" => "NO",
    "noruega" => "NO",
    "norwegen" => "NO",
    "norge" => "NO",

    # Denmark
    "dania" => "DK",
    "denmark" => "DK",
    "danemark" => "DK",
    "danimarca" => "DK",
    "dinamarca" => "DK",
    "dänemark" => "DK",
    "danmark" => "DK"
  }

  @doc """
  Resolves a country name (possibly in a foreign language) to a Countries struct.

  Returns the country if found, nil otherwise.

  ## Examples

      iex> CountryResolver.resolve("Polska")
      %Countries.Country{name: "Poland", ...}

      iex> CountryResolver.resolve("Deutschland")
      %Countries.Country{name: "Germany", ...}

      iex> CountryResolver.resolve("Poland")
      %Countries.Country{name: "Poland", ...}
  """
  def resolve(nil), do: nil
  def resolve(""), do: nil

  def resolve(name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()

    # First check our translation table for known localized names
    case Map.get(@translations, normalized) do
      nil ->
        # Try direct ISO code lookup (in case we already have a code)
        if String.length(normalized) <= 3 do
          case Countries.get(String.upcase(normalized)) do
            nil ->
              # Fall back to Countries library name search
              find_by_name(name)
            country ->
              # It was already a valid ISO code
              country
          end
        else
          # Fall back to Countries library name search
          find_by_name(name)
        end

      code ->
        country = Countries.get(code)
        if country do
          Logger.debug("CountryResolver: Translated '#{name}' to #{code} (#{country.name})")
        end
        country
    end
  end

  def resolve(_), do: nil

  @doc """
  Gets the ISO code for a country name.

  Returns the ISO code if found, nil otherwise.
  """
  def get_code(name) do
    case resolve(name) do
      nil -> nil
      %{alpha2: code} -> code
      _ -> nil
    end
  end

  @doc """
  Checks if we have a translation for the given country name.
  """
  def has_translation?(name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()
    Map.has_key?(@translations, normalized)
  end

  def has_translation?(_), do: false

  # Private function using Countries library search
  defp find_by_name(name) do
    # Try exact match first
    case Countries.filter_by(:name, name) do
      [country | _] -> country
      [] ->
        # Try unofficial names
        case Countries.filter_by(:unofficial_names, name) do
          [country | _] -> country
          [] ->
            # Try partial match on name
            Countries.all()
            |> Enum.find(fn country ->
              String.downcase(country.name) == String.downcase(name) ||
              (country.unofficial_names &&
               Enum.any?(country.unofficial_names, &(String.downcase(&1) == String.downcase(name))))
            end)
        end
    end
  end
end