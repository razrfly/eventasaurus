defmodule EventasaurusDiscovery.Sources.Sortiraparis.Extractors.VenueExtractor do
  @moduledoc """
  Extracts venue data from Sortiraparis HTML pages.

  ## Extraction Strategy

  Venues on Sortiraparis typically include:
  - Venue name (required)
  - Full address (required for geocoding)
  - City (Paris or surrounding areas)
  - Postal code
  - GPS coordinates (sometimes available)

  ## Geocoding Integration

  **IMPORTANT**: Do NOT geocode manually. Extract full address and let
  VenueProcessor handle geocoding via multi-provider system:

  1. Google Maps Geocoding API (primary)
  2. Nominatim (OpenStreetMap) (fallback)
  3. Photon (backup)

  See: [Geocoding System Documentation](../../../../docs/geocoding/GEOCODING_SYSTEM.md)

  ## Venue Data Format

  Returns map with:
  - `name` - Venue name (required)
  - `address` - Full street address (required)
  - `city` - City name (defaults to "Paris")
  - `postal_code` - ZIP/postal code (optional)
  - `country` - Country (defaults to "France")
  - `latitude` - GPS latitude (optional, if available)
  - `longitude` - GPS longitude (optional, if available)
  - `external_id` - Venue identifier (optional)
  - `metadata` - Additional venue info (optional)
  """

  require Logger
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer

  @doc """
  Extract venue data from HTML page.

  ## Parameters

  - `html` - HTML content as string

  ## Returns

  - `{:ok, venue_data}` - Map with venue fields
  - `{:error, reason}` - Extraction failed
  """
  def extract(html) when is_binary(html) do
    Logger.debug("🏛️ Extracting venue data from HTML")

    with {:ok, name} <- extract_venue_name(html),
         {:ok, address_data} <- extract_address_data(html) do
      # Extract optional GPS coordinates if available
      gps_coords = extract_gps_coordinates(html)

      venue_data = %{
        "name" => name,
        "address" => address_data[:full_address],
        "city" => address_data[:city] || "Paris",
        "postal_code" => address_data[:postal_code],
        "country" => "France",
        "latitude" => gps_coords[:latitude],
        "longitude" => gps_coords[:longitude],
        "metadata" => %{}
      }

      Logger.debug("✅ Successfully extracted venue: #{name}")
      {:ok, venue_data}
    else
      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to extract venue data: #{inspect(reason)}")
        error
    end
  end

  def extract(_), do: {:error, :invalid_input}

  @doc """
  Extract venue name from HTML.

  Tries multiple strategies:
  1. _mapHandler.init JavaScript (primary - embedded map data)
  2. Dedicated venue element with class "venue" or "location"
  3. Structured data (JSON-LD)
  4. Address block heading
  5. Title-based extraction (fallback)
  """
  def extract_venue_name(html) do
    cond do
      # Strategy 1: Extract from _mapHandler.init (primary - most reliable)
      name = extract_venue_from_map_handler(html) ->
        {:ok, name}

      # Strategy 2: Venue-specific element
      name = extract_venue_element(html) ->
        {:ok, name}

      # Strategy 3: JSON-LD structured data
      name = extract_venue_from_json_ld(html) ->
        {:ok, name}

      # Strategy 4: Search for common patterns
      name = extract_venue_from_text(html) ->
        {:ok, name}

      true ->
        {:error, :venue_name_not_found}
    end
  end

  @doc """
  Extract address data from HTML.

  Returns map with:
  - `:full_address` - Complete address string
  - `:city` - City name
  - `:postal_code` - ZIP/postal code
  """
  def extract_address_data(html) do
    cond do
      # Strategy 1: Schema.org structured address with itemprop (most common on Sortiraparis)
      address = extract_address_from_schema_org(html) ->
        {:ok, address}

      # Strategy 2: Structured address block
      address = extract_address_block(html) ->
        {:ok, parse_address(address)}

      # Strategy 3: JSON-LD structured data
      address = extract_address_from_json_ld(html) ->
        {:ok, address}

      # Strategy 4: Search text for address patterns
      address = extract_address_from_text(html) ->
        {:ok, parse_address(address)}

      true ->
        {:error, :address_not_found}
    end
  end

  @doc """
  Extract GPS coordinates if available in the page.

  Returns map with:
  - `:latitude` - Decimal latitude (nil if not found)
  - `:longitude` - Decimal longitude (nil if not found)
  """
  def extract_gps_coordinates(html) do
    cond do
      # Strategy 1: _mapHandler.init JavaScript (primary - most reliable)
      coords = extract_coords_from_map_handler(html) ->
        coords

      # Strategy 2: JSON-LD geo data
      coords = extract_coords_from_json_ld(html) ->
        coords

      # Strategy 3: Meta tags
      coords = extract_coords_from_meta(html) ->
        coords

      # Strategy 4: Embedded map data attributes
      coords = extract_coords_from_map(html) ->
        coords

      true ->
        %{latitude: nil, longitude: nil}
    end
  end

  # Private helper functions

  defp extract_venue_from_map_handler(html) do
    case extract_map_handler_data(html) do
      %{venue_name: name} when is_binary(name) and name != "" ->
        name

      _ ->
        nil
    end
  end

  defp extract_coords_from_map_handler(html) do
    case extract_map_handler_data(html) do
      %{latitude: lat, longitude: lon} when is_number(lat) and is_number(lon) ->
        %{latitude: lat, longitude: lon}

      _ ->
        nil
    end
  end

  defp extract_map_handler_data(html) do
    # Extract _mapHandler.init({...}); JavaScript call
    # Pattern: _mapHandler.init({"markers":[{"l":48.850483,"L":2.344081,"t":"Venue Name"}]});
    case Regex.run(~r{_mapHandler\.init\((\{[^;]+\})\);}s, html) do
      [_, json_str] ->
        case Jason.decode(json_str) do
          {:ok, %{"markers" => [first_marker | _]}} ->
            # Extract from first marker (primary venue for the event)
            %{
              latitude: Map.get(first_marker, "l"),
              longitude: Map.get(first_marker, "L"),
              venue_name: Map.get(first_marker, "t")
            }

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp extract_venue_element(html) do
    patterns = [
      ~r{<div[^>]*class="[^"]*venue[^"]*"[^>]*>(.*?)</div>}s,
      ~r{<span[^>]*class="[^"]*location[^"]*"[^>]*>(.*?)</span>}s,
      ~r{<h2[^>]*class="[^"]*venue[^"]*"[^>]*>(.*?)</h2>}s
    ]

    patterns
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, html) do
        [_, venue] -> Normalizer.clean_html(venue)
        _ -> nil
      end
    end)
  end

  defp extract_venue_from_json_ld(html) do
    case Regex.run(~r{<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>}s, html) do
      [_, json] ->
        case Jason.decode(json) do
          {:ok, %{"location" => %{"name" => name}}} -> name
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_venue_from_text(html) do
    text = Normalizer.clean_html(html)

    cond do
      # Strategy 1: Look for patterns like "Where: Venue Name" or "Location: Venue Name"
      venue = extract_venue_with_prefix(text) ->
        venue

      # Strategy 2: Extract venue from title (e.g., "The Musée de Cluny at night: ...")
      venue = extract_venue_from_title(html) ->
        venue

      true ->
        nil
    end
  end

  defp extract_venue_with_prefix(text) do
    case Regex.run(~r{(?:Where|Location|Venue):\s*([^\n,]+)}i, text) do
      [_, venue] -> String.trim(venue)
      _ -> nil
    end
  end

  defp extract_venue_from_title(html) do
    case Regex.run(~r{<title>(.+?)\s*[-|]\s*Sortiraparis}i, html) do
      [_, title] ->
        # Extract venue name from title patterns like:
        # "The Musée de Cluny at night: ..." -> "Musée de Cluny"
        # "Concert at Accor Arena" -> "Accor Arena"
        extract_venue_name_from_title_text(title)

      _ ->
        nil
    end
  end

  defp extract_venue_name_from_title_text(title) do
    cond do
      # Pattern: "The Venue Name at/in/..." (venue before at/in, must start with The)
      match = Regex.run(~r{The\s+([A-Z][^:,]+?)\s+(?:at|in)\s}i, title) ->
        [_, venue] = match
        clean_venue_name(venue)

      # Pattern: "at Venue Name" or "in Venue Name" (venue after at/in, must be proper noun)
      match =
          Regex.run(
            ~r{(?:at|in)\s+([A-Z][A-Za-z\s]+(?:Arena|Hall|Centre|Center|Palais|Museum|Theatre|Theater|Stadium))}i,
            title
          ) ->
        [_, venue] = match
        clean_venue_name(venue)

      # Generic pattern: "at/in Capitalized Name"
      match = Regex.run(~r{(?:at|in)\s+([A-Z][^:,\-|]+)}i, title) ->
        [_, venue] = match
        clean_venue_name(venue)

      true ->
        nil
    end
  end

  defp clean_venue_name(name) do
    name
    |> String.trim()
    |> String.replace(~r{\s+(at|in|the)\s*$}i, "")
    |> String.trim()
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  defp extract_address_from_schema_org(html) do
    # Extract Schema.org structured address with itemprop attributes
    # Instead of trying to match nested spans, extract each component directly from the HTML
    # This avoids issues with nested span tags

    # Check if there's a Schema.org address structure present
    has_schema_address =
      Regex.match?(
        ~r{<span[^>]*itemprop="address"[^>]*itemtype="http://schema\.org/PostalAddress"}sm,
        html
      )

    if has_schema_address do
      # Extract streetAddress directly from HTML
      street =
        case Regex.run(~r{<span[^>]*itemprop="streetAddress"[^>]*>(.*?)</span>}s, html) do
          [_, s] -> Normalizer.clean_html(s)
          _ -> nil
        end

      # Extract postalCode directly from HTML
      postal =
        case Regex.run(~r{<span[^>]*itemprop="postalCode"[^>]*>(.*?)</span>}s, html) do
          [_, p] -> Normalizer.clean_html(p)
          _ -> nil
        end

      # Extract addressLocality (city) directly from HTML
      city =
        case Regex.run(~r{<span[^>]*itemprop="addressLocality"[^>]*>(.*?)</span>}s, html) do
          [_, c] -> Normalizer.clean_html(c)
          _ -> nil
        end

      # Build full address if we have the components
      if street && postal && city do
        %{
          full_address: "#{street}, #{postal} #{city}",
          city: city,
          postal_code: postal
        }
      else
        nil
      end
    else
      nil
    end
  end

  defp extract_address_block(html) do
    patterns = [
      ~r{<address[^>]*>(.*?)</address>}s,
      ~r{<div[^>]*class="[^"]*address[^"]*"[^>]*>(.*?)</div>}s
    ]

    patterns
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, html) do
        [_, address] -> Normalizer.clean_html(address)
        _ -> nil
      end
    end)
  end

  defp extract_address_from_json_ld(html) do
    case Regex.run(~r{<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>}s, html) do
      [_, json] ->
        case Jason.decode(json) do
          {:ok, %{"location" => %{"address" => address_data}}} when is_map(address_data) ->
            %{
              full_address: build_full_address(address_data),
              city: address_data["addressLocality"],
              postal_code: address_data["postalCode"]
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp extract_address_from_text(html) do
    text = Normalizer.clean_html(html)

    # Look for Paris address pattern: "8 Boulevard de Bercy, 75012 Paris"
    case Regex.run(
           ~r/(\d+[^,]*,\s*\d{5}\s*Paris(?:\s+\d{1,2})?)/i,
           text
         ) do
      [_, address] -> String.trim(address)
      _ -> nil
    end
  end

  defp parse_address(address_string) when is_binary(address_string) do
    # Extract city (typically "Paris" or "Paris XX")
    city =
      case Regex.run(~r/Paris(?:\s+\d{1,2})?/, address_string) do
        [match] -> match
        _ -> "Paris"
      end

    # Extract postal code (5 digits)
    postal_code =
      case Regex.run(~r/\b(\d{5})\b/, address_string) do
        [_, code] -> code
        _ -> nil
      end

    %{
      full_address: address_string,
      city: city,
      postal_code: postal_code
    }
  end

  defp build_full_address(%{
         "streetAddress" => street,
         "addressLocality" => city,
         "postalCode" => postal
       }) do
    "#{street}, #{postal} #{city}"
  end

  defp build_full_address(_), do: nil

  defp extract_coords_from_json_ld(html) do
    case Regex.run(~r{<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>}s, html) do
      [_, json] ->
        case Jason.decode(json) do
          {:ok, %{"location" => %{"geo" => %{"latitude" => lat, "longitude" => lon}}}} ->
            %{latitude: parse_coordinate(lat), longitude: parse_coordinate(lon)}

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp extract_coords_from_meta(html) do
    # Look for geo meta tags: <meta name="geo.position" content="48.8566,2.3522">
    case Regex.run(~r{<meta\s+name="geo\.position"\s+content="([^"]+)"}i, html) do
      [_, coords] ->
        case String.split(coords, ",") do
          [lat, lon] -> %{latitude: parse_coordinate(lat), longitude: parse_coordinate(lon)}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_coords_from_map(html) do
    # Look for embedded map data: data-lat="48.8566" data-lng="2.3522"
    lat =
      case Regex.run(~r{data-lat="([^"]+)"}i, html) do
        [_, lat_str] -> parse_coordinate(lat_str)
        _ -> nil
      end

    lon =
      case Regex.run(~r{data-lng="([^"]+)"}i, html) do
        [_, lon_str] -> parse_coordinate(lon_str)
        _ -> nil
      end

    if lat && lon do
      %{latitude: lat, longitude: lon}
    else
      nil
    end
  end

  defp parse_coordinate(coord_string) when is_binary(coord_string) do
    case Float.parse(String.trim(coord_string)) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp parse_coordinate(coord) when is_number(coord), do: coord
  defp parse_coordinate(_), do: nil
end
