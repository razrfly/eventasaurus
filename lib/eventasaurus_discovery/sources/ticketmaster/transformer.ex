defmodule EventasaurusDiscovery.Sources.Ticketmaster.Transformer do
  @moduledoc """
  Transforms Ticketmaster API responses to our standardized schema.
  Handles the mapping of complex nested structures to our database format.
  """

  require Logger
  alias EventasaurusDiscovery.Helpers.CityResolver
  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

  @doc """
  Transforms a Ticketmaster event to our standardized event data structure.

  IMPORTANT: All events MUST have a venue with complete location data.
  Events without proper venue information will be rejected.

  Returns {:ok, transformed_event} or {:error, reason}
  """
  def transform_event(tm_event, locale \\ nil, city \\ nil) when is_map(tm_event) do
    # Data is already cleaned at HTTP client level
    title = tm_event["name"]
    description = extract_description(tm_event)

    # Extract and validate venue first since it's critical
    venue_data = extract_venue(tm_event, city)

    # Validate venue has required fields (same as Bandsintown)
    case validate_venue(venue_data) do
      :ok ->
        # Extract price information
        {min_price, max_price, currency, is_free} = extract_price_info(tm_event)

        # Determine language key from locale
        lang_key = locale_to_language_key(locale)

        # Extract stable ID from URL - this is consistent across locales
        stable_id = extract_stable_id(tm_event)

        transformed = %{
          external_id: stable_id,
          title: title,
          title_translations: extract_title_translations(title, lang_key),
          description_translations: extract_description_translations(description, lang_key),
          starts_at: parse_event_datetime(tm_event),
          ends_at: parse_event_end_datetime(tm_event),
          status: map_event_status(tm_event),
          # All Ticketmaster events are ticketed
          is_ticketed: true,
          venue_data: venue_data,
          performers: extract_performers(tm_event),
          # Pass raw event data for category extraction
          raw_event_data: tm_event,
          # Keep category_id for backward compatibility but it won't be used
          category_id: extract_category_id(tm_event),
          metadata: extract_event_metadata(tm_event),
          # Add source_url directly like other scrapers do
          source_url: tm_event["url"],
          # Add price fields
          min_price: min_price,
          max_price: max_price,
          currency: currency,
          is_free: is_free
        }

        {:ok, transformed}

      {:error, reason} ->
        Logger.error("""
        ❌ Ticketmaster event rejected due to invalid venue:
        Event: #{title}
        ID: #{tm_event["id"]}
        Reason: #{reason}
        Venue data: #{inspect(venue_data)}
        """)

        {:error, reason}
    end
  end

  @doc """
  Validates that venue data contains all required fields.
  Returns :ok if valid, {:error, reason} if not.
  """
  def validate_venue(venue_data) do
    cond do
      is_nil(venue_data) ->
        {:error, "Venue data is required"}

      is_nil(venue_data[:name]) || venue_data[:name] == "" ->
        {:error, "Venue name is required"}

      is_nil(venue_data[:latitude]) ->
        {:error, "Venue latitude is required for location"}

      is_nil(venue_data[:longitude]) ->
        {:error, "Venue longitude is required for location"}

      true ->
        :ok
    end
  end

  @doc """
  Transforms a Ticketmaster venue to our standardized venue data structure.
  """
  def transform_venue(tm_venue, city \\ nil) when is_map(tm_venue) do
    # Use the KNOWN country from city context, not the unreliable API response
    known_country =
      if city && city.country do
        city.country.name
      else
        # Fallback to API data only if no context (shouldn't happen)
        get_in(tm_venue, ["country", "name"]) || get_in(tm_venue, ["country", "countryCode"])
      end

    # Get coordinates
    latitude = get_in(tm_venue, ["location", "latitude"]) |> to_float()
    longitude = get_in(tm_venue, ["location", "longitude"]) |> to_float()

    # Get API city name
    api_city_name = get_in(tm_venue, ["city", "name"])

    # Resolve city name using CityResolver with coordinates
    {resolved_city, resolved_country} =
      resolve_location(latitude, longitude, api_city_name, known_country)

    %{
      external_id: "tm_venue_#{tm_venue["id"]}",
      name: tm_venue["name"],
      address: get_in(tm_venue, ["address", "line1"]),
      city: resolved_city,
      state: get_in(tm_venue, ["state", "name"]) || get_in(tm_venue, ["state", "stateCode"]),
      country: resolved_country,
      postal_code: tm_venue["postalCode"],
      latitude: latitude,
      longitude: longitude,
      timezone: tm_venue["timezone"],
      metadata: extract_venue_metadata(tm_venue)
    }
  end

  @doc """
  Transforms a Ticketmaster attraction/performer to our standardized performer data structure.
  """
  def transform_performer(tm_attraction) when is_map(tm_attraction) do
    # Data is already cleaned at HTTP client level
    %{
      "external_id" => "tm_performer_#{tm_attraction["id"]}",
      "name" => tm_attraction["name"],
      "type" => extract_performer_type(tm_attraction),
      "metadata" => extract_performer_metadata(tm_attraction),
      "image_url" => extract_performer_image(tm_attraction)
    }
  end

  # Private helper functions

  defp extract_title_translations(title, lang_key)
       when is_binary(title) and is_binary(lang_key) do
    # We explicitly requested this locale, so we know what language we got back
    # Ticketmaster returns content in the language we requested via the locale parameter
    %{lang_key => title}
  end

  defp extract_title_translations(title, nil) when is_binary(title) do
    # If no locale was specified, default to Polish for Kraków events
    # since that's the primary language for this market
    %{"pl" => title}
  end

  defp extract_title_translations(_, _), do: nil

  defp extract_description_translations(description, lang_key)
       when is_binary(description) and is_binary(lang_key) do
    # Same as titles - we know what language we requested
    %{lang_key => description}
  end

  defp extract_description_translations(description, nil) when is_binary(description) do
    # Default to Polish for Kraków events when no locale specified
    %{"pl" => description}
  end

  defp extract_description_translations(_, _), do: nil

  # Convert locale format (e.g., "pl-pl", "en-us") to language key (e.g., "pl", "en")
  defp locale_to_language_key(nil), do: nil

  defp locale_to_language_key(locale) when is_binary(locale) do
    # Take the first part of the locale (language code)
    locale
    |> String.downcase()
    |> String.split("-")
    |> List.first()
  end

  defp locale_to_language_key(_), do: nil

  # Extract stable ID from the event URL
  # The URL contains a numeric ID that's consistent across locales
  defp extract_stable_id(tm_event) do
    case tm_event["url"] do
      nil ->
        # Fallback to the original ID if no URL
        "tm_#{tm_event["id"]}"

      url when is_binary(url) ->
        # Extract the numeric ID from URLs like:
        # https://www.ticketmaster.pl/event/muzeum-banksy-bilety/741913259
        # https://www.ticketmaster.pl/event/muzeum-banksy-tickets/741913259?language=en-us
        case Regex.run(~r/\/(\d+)(?:\?|$)/, url) do
          [_, numeric_id] ->
            # Use the URL ID as the stable identifier
            "tm_url_#{numeric_id}"

          _ ->
            # If we can't extract the URL ID, fall back to the event ID
            Logger.warning("Could not extract URL ID from: #{url}, using event ID")
            "tm_#{tm_event["id"]}"
        end

      _ ->
        # Fallback for non-string URLs
        "tm_#{tm_event["id"]}"
    end
  end

  defp extract_description(event) do
    cond do
      event["info"] -> event["info"]
      event["pleaseNote"] -> event["pleaseNote"]
      event["description"] -> event["description"]
      true -> generate_description(event)
    end
  end

  defp generate_description(event) do
    parts = []

    # Add genre/classification info
    parts =
      if classifications = event["classifications"] do
        classification = List.first(classifications) || %{}
        genre = get_in(classification, ["genre", "name"])
        segment = get_in(classification, ["segment", "name"])

        if genre && segment do
          ["#{segment} - #{genre}" | parts]
        else
          parts
        end
      else
        parts
      end

    # Add price range info
    parts =
      if price_ranges = event["priceRanges"] do
        price = List.first(price_ranges) || %{}

        if min = price["min"] do
          ["Starting from #{min} #{price["currency"]}" | parts]
        else
          parts
        end
      else
        parts
      end

    # Add sale dates
    parts =
      if sales = get_in(event, ["sales", "public"]) do
        if start_date = sales["startDateTime"] do
          ["Tickets on sale: #{format_date(start_date)}" | parts]
        else
          parts
        end
      else
        parts
      end

    Enum.join(parts, ". ")
  end

  defp parse_event_datetime(event) do
    dates = event["dates"] || %{}
    start = dates["start"] || %{}

    datetime_string = start["dateTime"] || start["localDate"]

    case datetime_string do
      nil ->
        Logger.warning("No start date found for event #{event["id"]}")
        nil

      date_string ->
        parse_datetime_string(date_string, dates["timezone"])
    end
  end

  defp parse_event_end_datetime(event) do
    dates = event["dates"] || %{}

    # Ticketmaster rarely provides end times
    if end_date = dates["end"] do
      datetime_string = end_date["dateTime"] || end_date["localDate"]
      parse_datetime_string(datetime_string, dates["timezone"])
    else
      nil
    end
  end

  defp parse_datetime_string(datetime_string, venue_timezone) do
    cond do
      # Check if it's already a valid datetime with timezone
      String.contains?(datetime_string, "T") ->
        case DateTime.from_iso8601(datetime_string) do
          {:ok, datetime, _offset} ->
            datetime

          {:error, :missing_offset} ->
            # Parse as local time in venue timezone
            # Ticketmaster sends local times without timezone indicators
            parse_as_local_time(datetime_string, venue_timezone)

          _ ->
            Logger.warning("Could not parse datetime: #{datetime_string}")
            nil
        end

      # It's just a date, parse and add default time
      true ->
        case Date.from_iso8601(datetime_string) do
          {:ok, date} ->
            # Default to 8 PM in the venue's timezone
            time = ~T[20:00:00]
            timezone = venue_timezone || "Europe/Warsaw"

            # Create a NaiveDateTime first
            naive_datetime = NaiveDateTime.new!(date, time)

            # Convert to DateTime in the venue's timezone
            convert_to_utc(naive_datetime, timezone)

          _ ->
            Logger.warning("Could not parse date: #{datetime_string}")
            nil
        end
    end
  end

  defp parse_as_local_time(datetime_string, venue_timezone) do
    # Default to Poland timezone for events in Poland
    timezone = venue_timezone || "Europe/Warsaw"

    with {:ok, naive_dt} <- NaiveDateTime.from_iso8601(datetime_string) do
      convert_to_utc(naive_dt, timezone)
    else
      _ ->
        Logger.warning(
          "Could not parse local datetime: #{datetime_string} with timezone: #{timezone}"
        )

        nil
    end
  end

  defp convert_to_utc(naive_datetime, timezone) do
    # Use shared TimezoneConverter for consistent behavior across all scrapers
    EventasaurusDiscovery.Scraping.Helpers.TimezoneConverter.convert_local_to_utc(
      naive_datetime,
      timezone
    )
  end

  defp map_event_status(event) do
    status_code = get_in(event, ["dates", "status", "code"])

    case status_code do
      "onsale" -> "active"
      "offsale" -> "completed"
      "cancelled" -> "cancelled"
      "postponed" -> "postponed"
      "rescheduled" -> "rescheduled"
      _ -> "active"
    end
  end

  defp extract_venue(event, city) do
    venues = get_in(event, ["_embedded", "venues"]) || []

    case List.first(venues) do
      nil ->
        # Log critical error when venue is missing
        Logger.error("""
        ❌ CRITICAL: Ticketmaster event missing venue data!
        Event: #{event["name"]}
        ID: #{event["id"]}
        URL: #{event["url"]}
        Has _embedded: #{inspect(Map.has_key?(event, "_embedded"))}
        _embedded keys: #{if event["_embedded"], do: inspect(Map.keys(event["_embedded"])), else: "N/A"}
        Full event keys: #{inspect(Map.keys(event) |> Enum.take(20))}
        """)

        # Try to extract venue from alternative locations
        extract_venue_fallback(event, city)

      venue ->
        Logger.debug("✅ Ticketmaster venue found: #{venue["name"]}")
        transform_venue(venue, city)
    end
  end

  defp extract_venue_fallback(event, city) do
    # Use the KNOWN country from city context
    known_country = if city && city.country, do: city.country.name, else: nil

    # Try to build venue from other event data
    # Check if event has place or location info
    cond do
      # Check for place information
      place = event["place"] ->
        Logger.info("🔄 Attempting to build venue from place data")

        # Get coordinates
        latitude = get_in(place, ["location", "latitude"]) |> to_float()
        longitude = get_in(place, ["location", "longitude"]) |> to_float()

        # Get API city name
        api_city_name = get_in(place, ["city", "name"]) || place["city"]

        # Resolve city name using CityResolver
        {resolved_city, resolved_country} =
          resolve_location(latitude, longitude, api_city_name, known_country)

        %{
          external_id:
            "tm_place_#{place["id"] || :crypto.hash(:md5, inspect(place)) |> Base.encode16()}",
          name: place["name"] || "Unknown Venue",
          address: place["address"] || place["line1"],
          city: resolved_city,
          state: get_in(place, ["state", "name"]) || place["state"],
          country:
            resolved_country || known_country || get_in(place, ["country", "name"]) ||
              place["country"],
          postal_code: place["postalCode"],
          latitude: latitude,
          longitude: longitude,
          timezone: place["timezone"],
          metadata: %{}
        }

      # Check for location in event root
      location = event["location"] ->
        Logger.info("🔄 Attempting to build venue from location data")

        # Get coordinates
        latitude = location["latitude"] |> to_float()
        longitude = location["longitude"] |> to_float()

        # Resolve city name using CityResolver
        {resolved_city, resolved_country} =
          resolve_location(latitude, longitude, location["city"], known_country)

        %{
          external_id: "tm_location_#{:crypto.hash(:md5, inspect(location)) |> Base.encode16()}",
          name: location["name"] || "Unknown Venue",
          address: location["address"],
          city: resolved_city,
          state: location["state"],
          country: resolved_country || known_country || location["country"],
          postal_code: location["postalCode"],
          latitude: latitude,
          longitude: longitude,
          timezone: event["timezone"],
          metadata: %{}
        }

      # Check for any location-related info in dates
      dates = event["dates"] ->
        Logger.info("🔄 Attempting to extract location from dates/timezone")
        # If we have timezone, we can at least infer the general region
        timezone = dates["timezone"]
        {city_name, country_name, lat, lng} = infer_location_from_timezone(timezone)

        if city_name do
          %{
            external_id: "tm_inferred_#{event["id"]}",
            name: "Venue TBD - #{city_name}",
            address: nil,
            city: city_name,
            state: nil,
            country: known_country || country_name,
            postal_code: nil,
            latitude: lat,
            longitude: lng,
            timezone: timezone,
            metadata: %{inferred: true}
          }
        else
          nil
        end

      # Absolute last resort - create TBD venue with event name
      true ->
        Logger.warning("⚠️ No venue data found, creating TBD placeholder")
        # For Ticketmaster events, we should at least have a location from the API call
        # Default to Kraków since that's our primary city
        %{
          external_id: "tm_tbd_#{event["id"]}",
          name: "Venue TBD - Check Event Page",
          address: nil,
          city: "Kraków",
          state: nil,
          country: "Poland",
          postal_code: nil,
          # Kraków center
          latitude: 50.0647,
          longitude: 19.9450,
          timezone: "Europe/Warsaw",
          metadata: %{placeholder: true, needs_update: true}
        }
    end
  end

  defp infer_location_from_timezone(nil), do: {nil, nil, nil, nil}

  defp infer_location_from_timezone(timezone) do
    # Map common timezones to cities
    case timezone do
      "Europe/Warsaw" -> {"Warsaw", "Poland", 52.2297, 21.0122}
      # Note: Kraków uses Europe/Warsaw timezone in IANA tz database
      "Europe/London" -> {"London", "United Kingdom", 51.5074, -0.1278}
      "Europe/Paris" -> {"Paris", "France", 48.8566, 2.3522}
      "Europe/Berlin" -> {"Berlin", "Germany", 52.5200, 13.4050}
      "America/New_York" -> {"New York", "United States", 40.7128, -74.0060}
      "America/Los_Angeles" -> {"Los Angeles", "United States", 34.0522, -118.2437}
      "America/Chicago" -> {"Chicago", "United States", 41.8781, -87.6298}
      _ -> {nil, nil, nil, nil}
    end
  end

  defp extract_performers(event) do
    attractions = get_in(event, ["_embedded", "attractions"]) || []
    Enum.map(attractions, &transform_performer/1)
  end

  defp extract_category_id(event) do
    # Map Ticketmaster classifications to our category IDs
    # Categories: 1=Festivals, 2=Concerts, 3=Performances, 4=Literature, 5=Film, 6=Exhibitions

    classifications = event["classifications"] || []

    # Get the primary classification
    primary =
      Enum.find(classifications, fn c -> c["primary"] == true end) || List.first(classifications)

    if primary do
      segment = get_in(primary, ["segment", "name"])
      genre = get_in(primary, ["genre", "name"])

      case String.downcase(segment || "") do
        # Concerts
        "music" ->
          2

        # Map sports to Performances
        "sports" ->
          3

        "arts & theatre" ->
          case String.downcase(genre || "") do
            # Performances
            genre when genre in ["theatre", "theater", "dance", "opera", "musical"] -> 3
            # Film
            "film" -> 5
            # Default arts to Performances
            _ -> 3
          end

        # Film
        "film" ->
          5

        "miscellaneous" ->
          case String.downcase(genre || "") do
            # Festivals
            genre when genre in ["fairs & festivals", "festival"] -> 1
            # Default to Performances
            _ -> 3
          end

        # Default to Concerts
        _ ->
          2
      end
    else
      # Default to Concerts if no classification
      2
    end
  end

  defp extract_performer_type(attraction) do
    classifications = attraction["classifications"] || []

    case List.first(classifications) do
      nil ->
        "artist"

      classification ->
        segment = get_in(classification, ["segment", "name"])

        case String.downcase(segment || "") do
          "music" -> "band"
          "sports" -> "team"
          "arts" -> "artist"
          "theatre" -> "theater"
          _ -> "artist"
        end
    end
  end

  defp extract_event_metadata(event) do
    %{
      ticketmaster_data: %{
        id: event["id"],
        url: event["url"],
        locale: event["locale"],
        images: extract_images(event["images"]),
        price_ranges: event["priceRanges"],
        sales: event["sales"],
        classifications: event["classifications"],
        promoters: event["promoters"],
        seatmap: get_in(event, ["seatmap", "staticUrl"]),
        accessibility: event["accessibility"],
        ticket_limit: get_in(event, ["ticketLimit", "info"]),
        age_restrictions: event["ageRestrictions"],
        products: extract_products(event)
      },
      # Raw upstream data for debugging (sanitized for JSON)
      _raw_upstream: JsonSanitizer.sanitize(event)
    }
  end

  defp extract_venue_metadata(venue) do
    %{
      ticketmaster_data: %{
        id: venue["id"],
        url: venue["url"],
        locale: venue["locale"],
        images: extract_images(venue["images"]),
        parking_detail: venue["parkingDetail"],
        accessible_seating: venue["accessibleSeatingDetail"],
        general_info: venue["generalInfo"],
        box_office_info: venue["boxOfficeInfo"],
        social_media: venue["social"],
        ada: venue["ada"],
        upcoming_events: get_in(venue, ["upcomingEvents", "_total"])
      }
    }
  end

  defp extract_performer_metadata(attraction) do
    %{
      ticketmaster_data: %{
        id: attraction["id"],
        url: attraction["url"],
        locale: attraction["locale"],
        images: extract_images(attraction["images"]),
        classifications: attraction["classifications"],
        upcoming_events: get_in(attraction, ["upcomingEvents", "_total"]),
        external_links: extract_external_links(attraction["externalLinks"])
      }
    }
  end

  defp extract_performer_image(attraction) do
    # Get the first suitable image from the attraction
    images = attraction["images"] || []

    image =
      Enum.find(images, fn img ->
        # Prefer 16:9 ratio images, or take the first one
        img["ratio"] == "16_9" || img["ratio"] == "4_3"
      end) || List.first(images)

    if image, do: image["url"], else: nil
  end

  defp extract_images(nil), do: []

  defp extract_images(images) when is_list(images) do
    images
    |> Enum.map(fn img ->
      %{
        url: img["url"],
        ratio: img["ratio"],
        width: img["width"],
        height: img["height"],
        fallback: img["fallback"]
      }
    end)
    |> Enum.reject(fn img -> is_nil(img.url) end)
  end

  @doc """
  Extract prioritized images for multi-image caching.

  Selects the best images from Ticketmaster's image array, sorted by quality
  and assigned semantic types for caching.

  ## Image Types Assigned

  - Position 0: `"hero"` - Best 16:9 image (largest width)
  - Position 1: `"poster"` - Best 4:3 or 3:2 image
  - Position 2-4: `"gallery"` - Next best images by quality

  ## Returns

  List of image specs ready for EventImageCaching.cache_event_images/4:

      [
        %{url: "...", image_type: "hero", position: 0, metadata: %{...}},
        %{url: "...", image_type: "poster", position: 1, metadata: %{...}},
        ...
      ]
  """
  @spec extract_prioritized_images(list() | nil, integer()) :: list()
  def extract_prioritized_images(images, limit \\ 5)

  def extract_prioritized_images(nil, _limit), do: []
  def extract_prioritized_images([], _limit), do: []

  def extract_prioritized_images(images, limit) when is_list(images) do
    # Filter out nil URLs and fallback images first
    valid_images =
      images
      |> Enum.reject(fn img -> is_nil(img["url"]) || img["url"] == "" end)
      |> Enum.reject(fn img -> img["fallback"] == true end)

    # Group by ratio for selection
    by_ratio = Enum.group_by(valid_images, fn img -> img["ratio"] end)

    # Select hero (16:9, largest)
    hero = select_best_image(by_ratio["16_9"] || by_ratio["16_10"] || [], :largest)

    # Select poster (4:3 or 3:2, largest)
    poster = select_best_image(by_ratio["4_3"] || by_ratio["3_2"] || [], :largest)

    # Select remaining gallery images (sorted by quality)
    used_urls = [hero, poster] |> Enum.reject(&is_nil/1) |> Enum.map(& &1["url"]) |> MapSet.new()

    gallery =
      valid_images
      |> Enum.reject(fn img -> MapSet.member?(used_urls, img["url"]) end)
      |> Enum.sort_by(fn img -> -(img["width"] || 0) end)
      |> Enum.take(limit - 2)

    # Build image specs with full metadata
    specs = []

    specs =
      if hero do
        [build_image_spec(hero, "hero", 0) | specs]
      else
        # Fall back to any large image for hero
        fallback_hero = select_best_image(valid_images, :largest)

        if fallback_hero do
          [build_image_spec(fallback_hero, "hero", 0) | specs]
        else
          specs
        end
      end

    specs =
      if poster && poster != hero do
        [build_image_spec(poster, "poster", 1) | specs]
      else
        specs
      end

    # Add gallery images
    gallery_specs =
      gallery
      |> Enum.with_index(2)
      |> Enum.map(fn {img, pos} -> build_image_spec(img, "gallery", pos) end)

    (specs ++ gallery_specs)
    |> Enum.take(limit)
    |> Enum.sort_by(& &1.position)
  end

  # Select the best image from a list by criteria
  defp select_best_image([], _criteria), do: nil

  defp select_best_image(images, :largest) do
    Enum.max_by(images, fn img -> (img["width"] || 0) * (img["height"] || 0) end, fn -> nil end)
  end

  # Build image spec with full metadata preserved
  defp build_image_spec(img, image_type, position) do
    %{
      url: img["url"],
      image_type: image_type,
      position: position,
      metadata: %{
        "ratio" => img["ratio"],
        "width" => img["width"],
        "height" => img["height"],
        "fallback" => img["fallback"],
        "original_url" => img["url"],
        "source" => "ticketmaster",
        "extracted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  defp extract_products(event) do
    products = get_in(event, ["products"]) || []

    Enum.map(products, fn product ->
      %{
        id: product["id"],
        name: product["name"],
        type: product["type"],
        url: product["url"]
      }
    end)
  end

  defp extract_external_links(nil), do: %{}

  defp extract_external_links(links) do
    Enum.reduce(links, %{}, fn {platform, platform_links}, acc ->
      if is_list(platform_links) && length(platform_links) > 0 do
        link = List.first(platform_links)
        Map.put(acc, platform, link["url"])
      else
        acc
      end
    end)
  end

  defp format_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        Calendar.strftime(datetime, "%B %d, %Y")

      _ ->
        date_string
    end
  end

  defp to_float(nil), do: nil
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  @doc """
  Resolves city and country from GPS coordinates using offline geocoding.

  Uses CityResolver for reliable city name extraction from coordinates.
  Falls back to conservative validation of API-provided city name if geocoding fails.

  ## Parameters
  - `latitude` - GPS latitude coordinate
  - `longitude` - GPS longitude coordinate
  - `api_city` - City name from Ticketmaster API (fallback only)
  - `known_country` - Country from city context (preferred)

  ## Returns
  - `{city_name, country}` tuple
  """
  def resolve_location(latitude, longitude, api_city, known_country) do
    case CityResolver.resolve_city(latitude, longitude) do
      {:ok, city_name} ->
        # Successfully resolved city from coordinates
        {city_name, known_country}

      {:error, reason} ->
        # Geocoding failed - log and fall back to conservative validation
        Logger.warning(
          "Geocoding failed for (#{inspect(latitude)}, #{inspect(longitude)}): #{reason}. Falling back to API city validation."
        )

        validate_api_city(api_city, known_country)
    end
  end

  # Conservative fallback - validates API city name before using
  # Prefers nil over garbage data
  defp validate_api_city(api_city, known_country) when is_binary(api_city) do
    city_trimmed = String.trim(api_city)

    # CRITICAL: Validate city candidate before using
    case CityResolver.validate_city_name(city_trimmed) do
      {:ok, validated_city} ->
        {validated_city, known_country}

      {:error, reason} ->
        # City candidate failed validation (postcode, street address, etc.)
        Logger.warning(
          "Ticketmaster API returned invalid city: #{inspect(city_trimmed)} (#{reason})"
        )

        {nil, known_country}
    end
  end

  defp validate_api_city(_api_city, known_country) do
    {nil, known_country}
  end

  # Extract price information from priceRanges array
  # Returns {min_price, max_price, currency, is_free}
  #
  # NOTE: As of September 2025, Ticketmaster's Polish market API returns null
  # for all priceRanges fields, making price extraction impossible.
  # This infrastructure is retained for future API improvements.
  # See GitHub issue #1281 for details.
  defp extract_price_info(event) do
    case event["priceRanges"] do
      nil ->
        # No price data, not confirmed free
        {nil, nil, nil, false}

      [] ->
        # Empty price ranges, not confirmed free
        {nil, nil, nil, false}

      price_ranges when is_list(price_ranges) ->
        # Get all min and max prices
        all_prices =
          price_ranges
          |> Enum.flat_map(fn range ->
            prices = []
            prices = if range["min"], do: [range["min"] | prices], else: prices
            prices = if range["max"], do: [range["max"] | prices], else: prices
            prices
          end)
          |> Enum.filter(&is_number/1)

        if Enum.empty?(all_prices) do
          # No numeric prices found
          {nil, nil, nil, false}
        else
          # Get the absolute min and max across all price tiers
          min_price = Enum.min(all_prices)
          max_price = Enum.max(all_prices)

          # Check if event is free (all prices are 0)
          is_free = min_price == 0 && max_price == 0

          # Get currency from first price range that has it
          currency =
            price_ranges
            |> Enum.find_value(fn r -> r["currency"] end)
            |> case do
              curr when is_binary(curr) and byte_size(curr) > 0 -> String.upcase(curr)
              # Don't assume currency when not provided
              _ -> nil
            end

          # Return nil prices when free to comply with DB constraint
          if is_free do
            {nil, nil, currency, true}
          else
            {min_price, max_price, currency, false}
          end
        end

      _ ->
        {nil, nil, nil, false}
    end
  end
end
