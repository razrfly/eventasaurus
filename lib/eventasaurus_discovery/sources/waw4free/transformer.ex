defmodule EventasaurusDiscovery.Sources.Waw4Free.Transformer do
  @moduledoc """
  Transforms Waw4Free event data into the unified format expected by the Processor.

  IMPORTANT: All events MUST have a venue with complete location data.
  Events without proper venue information will be rejected.
  """

  require Logger

  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

  @doc """
  Transform a raw Waw4Free event into our unified format.

  Required fields for the unified format:
  - title
  - external_id
  - starts_at (DateTime)
  - venue (name required; coordinates will be geocoded by VenueProcessor)

  Optional fields:
  - description
  - ends_at
  - ticket_url
  - performers
  - category
  - is_free

  Returns {:ok, transformed_event} or {:error, reason}
  """
  def transform_event(raw_event) do
    # Extract and validate venue first since it's critical
    venue_data = extract_venue(raw_event)

    # Validate venue has required fields
    case validate_venue(venue_data) do
      :ok ->
        # Map Polish categories to English slugs (not IDs)
        # EventProcessor expects category as a STRING
        category_string =
          if raw_event[:categories] && length(raw_event[:categories]) > 0 do
            # Take first Polish category and map to English slug
            polish_category = List.first(raw_event[:categories])
            map_polish_to_english_category(polish_category)
          else
            nil
          end

        transformed = %{
          # Required fields
          title: extract_title(raw_event),
          external_id: raw_event[:external_id],
          starts_at: raw_event[:starts_at],
          ends_at: raw_event[:ends_at],

          # Venue data - REQUIRED and validated
          venue_data: venue_data,

          # Optional fields
          description: extract_description(raw_event),
          ticket_url: raw_event[:source_url],

          # Pricing - ALL waw4free events are free
          is_free: true,
          min_price: nil,
          max_price: nil,
          currency: "PLN",

          # Performer data (waw4free doesn't have separate performer info)
          performer: nil,

          # Categories and tags
          tags: [],
          category: category_string,

          # Translations (Polish)
          title_translations: %{"pl" => extract_title(raw_event)},
          description_translations:
            if(extract_description(raw_event),
              do: %{"pl" => extract_description(raw_event)},
              else: nil
            ),

          # Original URL for reference
          source_url: raw_event[:source_url],

          # Image
          image_url: raw_event[:image_url],

          # Metadata with raw upstream data for debugging
          metadata: %{
            "_raw_upstream" => JsonSanitizer.sanitize(raw_event)
          }
        }

        {:ok, transformed}

      {:error, reason} ->
        Logger.error("""
        ❌ Waw4Free event rejected due to invalid venue:
        Event: #{raw_event[:title]}
        URL: #{raw_event[:source_url]}
        Reason: #{reason}
        Venue data: #{inspect(venue_data)}
        """)

        {:error, reason}
    end
  end

  @doc """
  Validates that venue data contains all required fields.
  Returns :ok if valid, {:error, reason} if not.

  Note: Coordinates are optional - VenueProcessor will geocode if missing.
  """
  def validate_venue(venue_data) do
    cond do
      is_nil(venue_data) ->
        {:error, "Venue data is required"}

      is_nil(venue_data[:name]) || venue_data[:name] == "" ->
        {:error, "Venue name is required"}

      true ->
        :ok
    end
  end

  # Private functions

  defp extract_title(event) do
    event[:title] || "Unknown Event"
  end

  defp extract_description(event) do
    event[:description]
  end

  defp extract_venue(event) do
    venue_text = event[:venue]
    district = event[:district]

    cond do
      is_nil(venue_text) || venue_text == "" ->
        # No venue info available
        nil

      true ->
        # Parse venue info from text like "Warszawa - Śródmieście, ul. Złota 11, Restauracja Bliski Wschód"
        parsed = parse_venue_text(venue_text)

        %{
          name: parsed.name,
          address: parsed.address,
          city: "Warszawa",
          country: "Polska",
          district: district || parsed.district,
          latitude: nil,
          # Will be geocoded by VenueProcessor
          longitude: nil
          # Will be geocoded by VenueProcessor
        }
    end
  end

  defp parse_venue_text(venue_text) do
    # Try to extract venue name and address from text
    # Format examples:
    # "Warszawa - Śródmieście, ul. Złota 11, Restauracja Bliski Wschód"
    # "Warszawa - Mokotów, Park Łazienkowski"
    # "ul. Marszałkowska 10/16"

    parts = String.split(venue_text, ",")

    case parts do
      # Format: "City - District, Street, Venue Name"
      [city_district, street, venue_name] ->
        district = extract_district_from_city_text(city_district)

        %{
          name: String.trim(venue_name),
          address: "#{String.trim(street)}, Warszawa",
          district: district
        }

      # Format: "City - District, Venue Name" or "Street, Venue Name"
      [location, venue_name] ->
        district = extract_district_from_city_text(location)

        %{
          name: String.trim(venue_name),
          address:
            if(String.contains?(location, " - "),
              do: "Warszawa",
              else: "#{String.trim(location)}, Warszawa"
            ),
          district: district
        }

      # Single part - use as venue name
      [venue_only] ->
        %{
          name: String.trim(venue_only),
          address: "Warszawa",
          district: nil
        }

      _ ->
        # Fallback - use the whole text as venue name
        %{
          name: venue_text,
          address: "Warszawa",
          district: nil
        }
    end
  end

  defp extract_district_from_city_text(text) do
    # Extract district from "Warszawa - Śródmieście" format
    case String.split(text, " - ") do
      [_city, district] -> String.trim(district)
      _ -> nil
    end
  end

  # Map Polish category to English slug using YAML configuration
  defp map_polish_to_english_category(polish_category) when is_binary(polish_category) do
    # Simple mapping from waw4free.yml
    # In production, this would be loaded from YAML file
    mappings = %{
      "koncerty" => "concerts",
      "koncert" => "concerts",
      "warsztaty" => "education",
      "warsztat" => "education",
      "wystawy" => "arts",
      "wystawa" => "arts",
      "teatr" => "theatre",
      "teatry" => "theatre",
      "sport" => "sports",
      "sporty" => "sports",
      "dla-dzieci" => "family",
      "dla dzieci" => "family",
      "dzieci" => "family",
      "festiwale" => "festivals",
      "festiwal" => "festivals",
      "inne" => "other",
      # Music related
      "muzyka" => "concerts",
      "muzyczne" => "concerts",
      "muzyczny" => "concerts",
      "jazzowe" => "concerts",
      "rockowe" => "concerts",
      # Arts related
      "klasyczne" => "arts",
      "galeria" => "arts",
      "muzeum" => "arts",
      "performance" => "theatre",
      "spektakl" => "theatre",
      "spektakle" => "theatre",
      "balet" => "arts",
      "taniec" => "arts",
      "opera" => "arts",
      # Other
      "rodzinne" => "family",
      "edukacyjne" => "education",
      "sportowe" => "sports",
      "kulturalne" => "arts",
      "plenerowe" => "festivals"
    }

    # Normalize input (lowercase, trim)
    normalized = polish_category |> String.downcase() |> String.trim()

    # Look up mapping, return English slug or nil
    Map.get(mappings, normalized)
  end

  defp map_polish_to_english_category(_), do: nil
end
