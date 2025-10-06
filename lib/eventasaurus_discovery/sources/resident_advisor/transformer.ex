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
          performer: extract_performer(event),

          # Categories and tags
          tags: extract_tags(event),

          # No pricing data from RA
          min_price: nil,
          max_price: nil,
          currency: nil,

          # Original URL for reference
          source_url: Config.build_event_url(event["contentUrl"]),

          # Raw data for debugging (including promoter info for container grouping)
          raw_data: Map.merge(raw_event, extract_promoter_data(event))
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
      # Try to get coordinates from RA GraphQL (usually returns nil)
      # VenueProcessor will handle Google Places lookup automatically if nil
      # This follows the same pattern as Cinema City scraper
      {lat, lng, _needs_geocoding} =
        VenueEnricher.get_coordinates(
          venue["id"],
          venue["name"],
          city_context
        )

      %{
        name: venue["name"],
        address: nil,
        # RA doesn't provide address
        latitude: lat,
        longitude: lng,
        city: city_context.name,
        country: get_country_name(city_context),
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
      %{
        name: "Venue TBD - #{city_context.name}",
        address: nil,
        latitude: nil,
        longitude: nil,
        city: city_context.name,
        country: get_country_name(city_context),
        metadata: %{placeholder: true}
      }
    end
  end

  defp get_country_name(%{country: %{name: name}}), do: name
  defp get_country_name(_), do: nil

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

  defp is_featured?(event) do
    !is_nil(event["pick"])
  end

  defp extract_performer(event) do
    artists = event["artists"] || []

    if length(artists) > 0 do
      # Take first artist as primary performer
      first_artist = List.first(artists)

      %{
        name: first_artist["name"],
        # RA doesn't provide genres in event listing
        genres: [],
        # No artist images in event listing
        image_url: nil,
        metadata: %{
          ra_artist_id: first_artist["id"],
          all_artists: Enum.map(artists, & &1["name"])
        }
      }
    else
      nil
    end
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
      raw_data: Map.merge(raw_event, extract_promoter_data(event)),
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
