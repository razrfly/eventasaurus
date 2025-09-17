defmodule EventasaurusDiscovery.Sources.Karnet.VenueMatcher do
  @moduledoc """
  Simplified venue matcher for Kraków venues from Karnet.

  Since Karnet is localized to Kraków and lower priority, this provides
  basic venue matching without complex geocoding. Most major Kraków venues
  will likely already exist from Ticketmaster/BandsInTown imports.
  """

  require Logger

  # Common Kraków venues with their normalized names
  # This helps match Polish venue names to existing records
  @known_venues %{
    "ice kraków" => "Centrum Kongresowe ICE Kraków",
    "ice krakow" => "Centrum Kongresowe ICE Kraków",
    "centrum kongresowe ice" => "Centrum Kongresowe ICE Kraków",
    "tauron arena" => "Tauron Arena Kraków",
    "tauron arena kraków" => "Tauron Arena Kraków",
    "teatr słowackiego" => "Teatr im. J. Słowackiego",
    "teatr slowackiego" => "Teatr im. J. Słowackiego",
    "nowohuckie centrum kultury" => "Nowohuckie Centrum Kultury",
    "nck" => "Nowohuckie Centrum Kultury",
    "cricoteka" => "Cricoteka",
    "mocak" => "MOCAK",
    "muzeum narodowe" => "Muzeum Narodowe w Krakowie",
    "gmach główny" => "Muzeum Narodowe w Krakowie - Gmach Główny",
    "fabryka schindlera" => "Fabryka Emalia Oskara Schindlera",
    "manggha" => "Muzeum Sztuki i Techniki Japońskiej Manggha",
    "opera krakowska" => "Opera Krakowska",
    "filharmonia" => "Filharmonia Krakowska",
    "klub studio" => "Klub Studio",
    "kwadrat" => "Klub Kwadrat",
    "pod baranami" => "Piwnica pod Baranami",
    "rynek główny" => "Rynek Główny",
    "plac szczepański" => "Plac Szczepański",
    "błonia" => "Błonia Krakowskie",
    "wawel" => "Zamek Królewski na Wawelu"
  }

  @doc """
  Match a venue name to a normalized venue for Kraków.
  Returns a venue data map suitable for VenueProcessor.
  """
  def match_venue(venue_text) when is_binary(venue_text) do
    normalized = normalize_venue_name(venue_text)

    # Check if it's a known venue
    known_name = Map.get(@known_venues, normalized)

    venue_data = %{
      name: known_name || clean_venue_name(venue_text),
      original_name: venue_text,
      city: "Kraków",
      state: "Lesser Poland",
      country: "Poland",
      country_code: "PL",
      source: "karnet"
    }

    # Extract address if present
    if address = extract_address(venue_text) do
      Map.put(venue_data, :address, address)
    else
      venue_data
    end
  end

  def match_venue(nil), do: nil

  defp normalize_venue_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/u, "")  # Remove punctuation
    |> String.replace(~r/\s+/, " ")       # Normalize spaces
    |> String.trim()
  end

  defp clean_venue_name(name) do
    name
    |> String.split(",")      # Take first part if address included
    |> List.first()
    |> String.trim()
  end

  defp extract_address(text) do
    # Common Polish street prefixes
    street_patterns = [
      ~r/ul\.\s+[^,]+/,      # ul. (ulica - street)
      ~r/al\.\s+[^,]+/,      # al. (aleja - avenue)
      ~r/plac\s+[^,]+/i,     # plac (square)
      ~r/rynek\s+[^,]+/i     # rynek (market square)
    ]

    Enum.find_value(street_patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [match] -> String.trim(match)
        _ -> nil
      end
    end)
  end

  @doc """
  Get coordinates for known Kraków venues.
  Returns {lat, lng} or nil if not found.

  Note: In production, these would come from a geocoding service
  or be stored in the database. For now, hardcoding major venues.
  """
  def get_venue_coordinates(venue_name) do
    # Major Kraków venues with approximate coordinates
    coordinates = %{
      "Centrum Kongresowe ICE Kraków" => {50.0647, 19.9450},
      "Tauron Arena Kraków" => {50.0669, 20.0176},
      "Teatr im. J. Słowackiego" => {50.0640, 19.9415},
      "Nowohuckie Centrum Kultury" => {50.0676, 20.0367},
      "MOCAK" => {50.0475, 19.9615},
      "Muzeum Narodowe w Krakowie - Gmach Główny" => {50.0604, 19.9240},
      "Opera Krakowska" => {50.0672, 19.9551},
      "Filharmonia Krakowska" => {50.0642, 19.9382},
      "Rynek Główny" => {50.0617, 19.9373},
      "Wawel" => {50.0541, 19.9352}
    }

    coordinates[venue_name]
  end

  @doc """
  Process venue data for integration with VenueProcessor.
  """
  def prepare_venue_for_processor(venue_data) when is_map(venue_data) do
    # Ensure required fields for VenueProcessor
    base_venue = %{
      name: venue_data[:name] || venue_data["name"],
      city: venue_data[:city] || venue_data["city"] || "Kraków",
      country: venue_data[:country] || venue_data["country"] || "Poland"
    }

    # Add optional fields if available
    venue = if venue_data[:address] || venue_data["address"] do
      Map.put(base_venue, :address, venue_data[:address] || venue_data["address"])
    else
      base_venue
    end

    # Add coordinates if available for known venues
    if coords = get_venue_coordinates(base_venue.name) do
      {lat, lng} = coords
      venue
      |> Map.put(:latitude, lat)
      |> Map.put(:longitude, lng)
    else
      venue
    end
  end

  def prepare_venue_for_processor(nil), do: nil
end