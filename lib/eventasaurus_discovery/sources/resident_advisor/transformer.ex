defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Transformer do
  @moduledoc """
  Transforms Resident Advisor GraphQL data into the unified format expected by the Processor.

  IMPORTANT: All events MUST have a venue with complete location data.
  Events without proper venue information will be rejected.

  RA GraphQL provides rich event data but NO venue coordinates, so we use
  Google Places API geocoding to obtain them.
  """

  require Logger
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.{VenueEnricher, Config, UmbrellaDetector}
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Helpers.DateParser
  alias EventasaurusDiscovery.Helpers.CityResolver
  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

  @doc """
  Transform a raw RA GraphQL event into our unified format.

  Required fields for the unified format:
  - title
  - external_id
  - starts_at (DateTime)
  - venue (with name, latitude, longitude, address)

  Optional fields:
  - description
  - ends_at
  - ticket_url
  - performer
  - tags
  - image_url

  Returns {:ok, transformed_event} or {:error, reason}
  """
  def transform_event(raw_event, city_context) do
    # Extract event from wrapper (RA returns {id, listingDate, event})
    event = extract_event_data(raw_event)

    # Check if this is an umbrella/festival container event
    case UmbrellaDetector.is_umbrella_event?(event, city_context) do
      {:umbrella, metadata} ->
        # This is an umbrella event - return special marker for container creation
        UmbrellaDetector.log_detection(event, {:umbrella, metadata})
        {:umbrella, build_umbrella_event_data(raw_event, event, metadata, city_context)}

      :not_umbrella ->
        # Normal event - proceed with standard transformation
        transform_regular_event(raw_event, event, city_context)
    end
  end

  defp transform_regular_event(raw_event, event, city_context) do
    # Extract and validate venue first since it's critical
    venue_data = extract_venue(event, city_context)

    # Validate venue has required fields
    case validate_venue(venue_data) do
      :ok ->
        transformed = %{
          # Required fields
          title: extract_title(event),
          external_id: extract_external_id(event),
          starts_at: extract_starts_at(event, city_context),
          ends_at: extract_ends_at(event, city_context),

          # Venue data - REQUIRED and validated
          venue_data: venue_data,

          # Optional fields
          description: extract_description(event),
          ticket_url: build_ticket_url(event),
          image_url: extract_image_url(event),

          # RA-specific fields
          is_ticketed: event["isTicketed"] || false,
          attending_count: event["attending"],
          is_featured: is_featured?(event),

          # Performer data
          performers: extract_performers(event),

          # Categories and tags
          tags: extract_tags(event),

          # No pricing data from RA
          min_price: nil,
          max_price: nil,
          currency: nil,

          # Original URL for reference
          source_url: Config.build_event_url(event["contentUrl"]),

          # Metadata with raw upstream data for debugging (including promoter info for container grouping)
          metadata: %{
            "_raw_upstream" =>
              JsonSanitizer.sanitize(Map.merge(raw_event, extract_promoter_data(event)))
          }
        }

        {:ok, transformed}

      {:error, reason} ->
        Logger.error("""
        ❌ Resident Advisor event rejected due to invalid venue:
        Event: #{event["title"]}
        ID: #{event["id"]}
        URL: #{event["contentUrl"]}
        Reason: #{reason}
        Venue data: #{inspect(venue_data)}
        """)

        {:error, reason}
    end
  end

  @doc """
  Validates that venue data contains all required fields.

  Note: GPS coordinates are NOT required here - VenueProcessor handles geocoding automatically.
  This follows the same pattern as Cinema City scraper.

  Returns :ok if valid, {:error, reason} if not.
  """
  def validate_venue(nil), do: {:error, "Venue data is required"}

  def validate_venue(venue_data) do
    cond do
      is_nil(venue_data[:name]) || venue_data[:name] == "" ->
        {:error, "Venue name is required"}

      true ->
        :ok
    end
  end

  # Private functions

  defp extract_event_data(%{"event" => event}) when not is_nil(event), do: event
  defp extract_event_data(event), do: event

  defp extract_venue(event, city_context) do
    venue = event["venue"]

    if venue && venue["name"] do
      # Get coordinates from RA GraphQL via VenueEnricher (may return nil)
      {lat, lng, _needs_geocoding} =
        VenueEnricher.get_coordinates(
          venue["id"],
          venue["name"],
          city_context
        )

      # A-grade city resolution: Use CityResolver with GPS coordinates (primary)
      # or validate API city name (fallback)
      {resolved_city, resolved_country} =
        resolve_location(
          lat,
          lng,
          city_context.name,
          get_country_name(city_context)
        )

      %{
        name: venue["name"],
        address: nil,
        # RA doesn't provide address
        latitude: lat,
        longitude: lng,
        city: resolved_city,
        country: resolved_country,
        external_venue_id: venue["id"],
        source_url: Config.build_venue_url(venue["contentUrl"]),
        metadata: %{
          ra_venue_id: venue["id"],
          live: venue["live"]
        }
      }
    else
      Logger.warning("""
      ⚠️  No venue data for RA event, creating placeholder:
      Event: #{event["title"]}
      ID: #{event["id"]}
      """)

      # Create placeholder venue - VenueProcessor will geocode if needed
      # Validate city name even for placeholders
      {resolved_city, resolved_country} =
        resolve_location(
          nil,
          nil,
          city_context.name,
          get_country_name(city_context)
        )

      %{
        name: "Venue TBD - #{city_context.name}",
        address: nil,
        latitude: nil,
        longitude: nil,
        city: resolved_city,
        country: resolved_country,
        metadata: %{placeholder: true}
      }
    end
  end

  defp get_country_name(%{country: %{name: name}}), do: name
  defp get_country_name(_), do: nil

  # Resolve city and country from GPS coordinates or validate API city name.
  #
  # Strategy (A-grade implementation):
  # 1. If GPS coordinates available → Use CityResolver.resolve_city() (primary)
  # 2. If geocoding fails → Validate API city name with CityResolver.validate_city_name() (fallback)
  # 3. If validation fails → Return nil for city (safe default, VenueProcessor Layer 2 will catch)
  #
  # Pattern: International events with GPS fallback to API city validation.
  # Similar to Bandsintown A-grade pattern.
  #
  # Returns: {city_name | nil, country_name}
  defp resolve_location(latitude, longitude, api_city, country_name)
       when is_float(latitude) and is_float(longitude) do
    case CityResolver.resolve_city(latitude, longitude) do
      {:ok, city_name} ->
        Logger.debug("""
        ✅ ResidentAdvisor: CityResolver resolved city from GPS coordinates
        Coordinates: #{latitude}, #{longitude}
        Resolved city: #{city_name}
        Country: #{country_name}
        """)

        {city_name, country_name}

      {:error, reason} ->
        Logger.warning("""
        ⚠️  ResidentAdvisor: CityResolver geocoding failed (#{reason}), falling back to API city validation
        Coordinates: #{latitude}, #{longitude}
        API city: #{inspect(api_city)}
        """)

        validate_api_city(api_city, country_name)
    end
  end

  defp resolve_location(_latitude, _longitude, api_city, country_name) do
    Logger.debug("""
    ⚠️  ResidentAdvisor: No GPS coordinates available, validating API city name
    API city: #{inspect(api_city)}
    Country: #{country_name}
    """)

    validate_api_city(api_city, country_name)
  end

  # Validate API city name using CityResolver validation rules.
  #
  # Strategy:
  # - Use CityResolver.validate_city_name() to reject invalid patterns
  # - Return nil if validation fails (safe default for VenueProcessor Layer 2)
  #
  # Returns: {validated_city_name | nil, country_name}
  defp validate_api_city(api_city, country_name) when is_binary(api_city) do
    case CityResolver.validate_city_name(String.trim(api_city)) do
      {:ok, validated_city} ->
        Logger.debug("""
        ✅ ResidentAdvisor: API city name validated successfully
        API city: #{api_city}
        Validated: #{validated_city}
        """)

        {validated_city, country_name}

      {:error, reason} ->
        Logger.warning("""
        ❌ ResidentAdvisor: API city failed validation (#{reason})
        API city: #{inspect(api_city)}
        Returning nil for VenueProcessor Layer 2 safety net
        """)

        {nil, country_name}
    end
  end

  defp validate_api_city(nil, country_name) do
    Logger.debug("⚠️  ResidentAdvisor: No API city provided, returning nil")
    {nil, country_name}
  end

  defp validate_api_city(_invalid, country_name) do
    Logger.warning("⚠️  ResidentAdvisor: Invalid API city type, returning nil")
    {nil, country_name}
  end

  defp extract_title(event), do: event["title"] || "Unknown Event"

  defp extract_external_id(event) do
    "resident_advisor_#{event["id"]}"
  end

  defp extract_starts_at(event, city_context) do
    date = event["date"]
    start_time = event["startTime"]
    timezone = DateParser.infer_timezone(city_context)

    case DateParser.parse_start_datetime(date, start_time, timezone) do
      nil ->
        Logger.warning("""
        ⚠️  No valid start date for RA event, using default
        Event: #{event["title"]}
        Date: #{inspect(date)}
        Time: #{inspect(start_time)}
        """)

        # Default to tomorrow 20:00 UTC
        DateTime.utc_now()
        |> DateTime.add(86400, :second)
        |> DateTime.to_date()
        |> Date.to_string()
        |> DateParser.parse_start_datetime("20:00", "Etc/UTC")

      start_dt ->
        start_dt
    end
  end

  defp extract_ends_at(event, city_context) do
    date = event["date"]
    end_time = event["endTime"]

    if end_time do
      timezone = DateParser.infer_timezone(city_context)
      start_dt = extract_starts_at(event, city_context)

      DateParser.parse_end_datetime(date, end_time, start_dt, timezone)
    else
      nil
    end
  end

  defp extract_description(event) do
    # Use editorial pick blurb if available
    pick_blurb = get_in(event, ["pick", "blurb"])

    if pick_blurb && pick_blurb != "" do
      pick_blurb
    else
      nil
    end
  end

  defp build_ticket_url(event) do
    Config.build_event_url(event["contentUrl"])
  end

  defp extract_image_url(event) do
    cond do
      # Prefer flyerFront
      event["flyerFront"] && event["flyerFront"] != "" ->
        event["flyerFront"]

      # Fall back to first image in images array
      event["images"] && length(event["images"]) > 0 ->
        first_image = List.first(event["images"])
        first_image["filename"]

      true ->
        nil
    end
  end

  @doc """
  Extract all available images for multi-image caching.

  RA provides:
  - `flyerFront` - Primary flyer image (assigned as "hero")
  - `images` array - Additional images (assigned as "gallery")

  ## Returns

  List of image specs ready for EventImageCaching.cache_event_images/4:

      [
        %{url: "...", image_type: "hero", position: 0, metadata: %{...}},
        %{url: "...", image_type: "gallery", position: 1, metadata: %{...}},
        ...
      ]
  """
  @spec extract_all_images(map(), integer()) :: list()
  def extract_all_images(event, limit \\ 5)

  def extract_all_images(event, limit) when is_map(event) do
    specs = []
    position = 0

    # Extract flyerFront as hero (position 0)
    {specs, position} =
      case event["flyerFront"] do
        url when is_binary(url) and url != "" ->
          spec = %{
            url: url,
            image_type: "hero",
            position: position,
            metadata: %{
              "source" => "resident_advisor",
              "image_source" => "flyerFront",
              "ra_event_id" => event["id"],
              "original_url" => url,
              "extracted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          }

          {[spec | specs], position + 1}

        _ ->
          {specs, position}
      end

    # Extract images array as gallery
    gallery_specs =
      case event["images"] do
        images when is_list(images) and length(images) > 0 ->
          images
          |> Enum.take(limit - position)
          |> Enum.with_index(position)
          |> Enum.map(fn {img, pos} ->
            url = img["filename"] || img["url"]

            if url && url != "" do
              %{
                url: url,
                image_type: "gallery",
                position: pos,
                metadata: %{
                  "source" => "resident_advisor",
                  "image_source" => "images_array",
                  "ra_event_id" => event["id"],
                  "original_url" => url,
                  "image_id" => img["id"],
                  "extracted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
                }
              }
            else
              nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    (Enum.reverse(specs) ++ gallery_specs)
    |> Enum.take(limit)
  end

  def extract_all_images(_, _limit), do: []

  defp is_featured?(event) do
    !is_nil(event["pick"])
  end

  defp extract_performers(event) do
    artists = event["artists"] || []

    # Return all artists as performers with enriched data
    Enum.map(artists, fn artist ->
      # Extract country information if available
      country_name = get_in(artist, ["country", "name"])
      country_code = get_in(artist, ["country", "urlCode"])

      # Build artist profile URL if contentUrl available
      artist_url =
        if artist["contentUrl"] do
          "https://ra.co#{artist["contentUrl"]}"
        else
          nil
        end

      %{
        name: artist["name"],
        # RA doesn't provide genres in event listing GraphQL
        genres: [],
        # Image URL from artist profile
        image_url: artist["image"],
        metadata: %{
          ra_artist_id: artist["id"],
          ra_artist_url: artist_url,
          country: country_name,
          country_code: country_code,
          source: "resident_advisor"
        }
      }
    end)
  end

  defp extract_tags(event) do
    tags = ["electronic-music", "resident-advisor"]

    # Add ticketing tag
    tags = if event["isTicketed"], do: ["ticketed" | tags], else: ["free" | tags]

    # Add featured tag
    tags = if is_featured?(event), do: ["featured" | tags], else: tags

    # Add queue system tag
    tags = if event["queueItEnabled"], do: ["high-demand" | tags], else: tags

    # Add attendance if significant
    if event["attending"] && event["attending"] > 100 do
      ["popular" | tags]
    else
      tags
    end
    |> Enum.uniq()
  end

  # Build umbrella event data for container creation.
  # Returns event data in a format suitable for PublicEventContainers.create_from_umbrella_event/2
  defp build_umbrella_event_data(raw_event, event, metadata, city_context) do
    %{
      title: extract_title(event),
      external_id: extract_external_id(event),
      starts_at: extract_starts_at(event, city_context),
      ends_at: extract_ends_at(event, city_context),
      description: extract_description(event),
      image_url: extract_image_url(event),
      metadata: %{
        "_raw_upstream" =>
          JsonSanitizer.sanitize(Map.merge(raw_event, extract_promoter_data(event)))
      },
      umbrella_metadata: metadata,
      tags: ["festival", "resident-advisor"]
    }
  end

  # Extract promoter information from event data for container grouping.
  # This data is used by ContainerGrouper to group events by promoter ID.
  defp extract_promoter_data(event) do
    case event["promoters"] do
      [%{"id" => id, "name" => name} | _] ->
        %{"promoter_id" => id, "promoter_name" => name}

      _ ->
        %{"promoter_id" => nil, "promoter_name" => nil}
    end
  end
end
