defmodule EventasaurusDiscovery.Sources.Karnet.VenueMatcher do
  @moduledoc """
  Simplified venue matcher for Kraków venues from Karnet.

  Provides venue name normalization and basic address extraction.
  Coordinates are obtained through VenueProcessor using Google Places API.
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
    # Remove punctuation
    |> String.replace(~r/[^\w\s]/u, "")
    # Normalize spaces
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp clean_venue_name(name) do
    name
    # Take first part if address included
    |> String.split(",")
    |> List.first()
    |> String.trim()
  end

  defp extract_address(text) do
    # Common Polish street prefixes
    street_patterns = [
      # ul. (ulica - street)
      ~r/ul\.\s+[^,]+/,
      # al. (aleja - avenue)
      ~r/al\.\s+[^,]+/,
      # plac (square)
      ~r/plac\s+[^,]+/i,
      # rynek (market square)
      ~r/rynek\s+[^,]+/i
    ]

    Enum.find_value(street_patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [match] -> String.trim(match)
        _ -> nil
      end
    end)
  end

  @doc """
  Process venue data for integration with VenueProcessor.

  Returns venue data with nil coordinates to trigger automatic lookup
  via Google Places API through VenueProcessor.
  """
  def prepare_venue_for_processor(venue_data) when is_map(venue_data) do
    # Ensure required fields for VenueProcessor
    base_venue = %{
      name: venue_data[:name] || venue_data["name"],
      city: venue_data[:city] || venue_data["city"] || "Kraków",
      country: venue_data[:country] || venue_data["country"] || "Poland",
      # Set coordinates to nil to trigger Google Places lookup
      latitude: nil,
      longitude: nil
    }

    # Add optional address if available
    if venue_data[:address] || venue_data["address"] do
      Map.put(base_venue, :address, venue_data[:address] || venue_data["address"])
    else
      base_venue
    end
  end

  def prepare_venue_for_processor(nil), do: nil
end
