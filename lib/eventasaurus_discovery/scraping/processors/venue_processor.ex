defmodule EventasaurusDiscovery.Scraping.Processors.VenueProcessor do
  @moduledoc """
  Processes venue data from various sources and ensures proper
  city and country relationships.

  Handles:
  - Finding or creating venues
  - Associating venues with cities
  - Deduplication based on place_id
  - Google Places integration
  """

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Venues.DuplicateDetection
  alias EventasaurusDiscovery.Locations.{City, Country, CountryResolver}
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer
  alias EventasaurusDiscovery.Helpers.{CityResolver, AddressGeocoder}
  alias EventasaurusDiscovery.Geocoding.MetadataBuilder
  alias EventasaurusDiscovery.Validation.VenueNameValidator

  import Ecto.Query
  require Logger

  # ========================================
  # Venue Matching Configuration
  # ========================================
  # Duplicate detection now uses unified DuplicateDetection module with distance-based
  # similarity thresholds. See EventasaurusApp.Venues.DuplicateDetection for details.
  #
  # Legacy threshold constants kept for name-only matching fallback:
  # PostgreSQL similarity() function threshold (uses trigram matching)
  @postgres_similarity_threshold 0.6

  # ========================================
  # End Configuration
  # ========================================

  @doc """
  Processes venue data and returns a venue record.
  Creates or finds existing venue, city, and country as needed.

  ## Parameters
  - `venue_data` - Raw venue data from scraper
  - `source` - Source type ("scraper", "user", "google")
  - `source_scraper` - Optional scraper name for cost tracking (e.g., "question_one", "kino_krakow")
  """
  def process_venue(venue_data, source \\ "scraper", source_scraper \\ nil) do
    # Data is already cleaned at HTTP client level (single entry point validation)
    with {:ok, normalized_data} <- normalize_venue_data(venue_data),
         {:ok, city} <- ensure_city(normalized_data),
         {:ok, venue} <- find_or_create_venue(normalized_data, city, source, source_scraper) do
      {:ok, venue}
    else
      {:error, reason} = error ->
        Logger.error("Failed to process venue: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Finds an existing venue by place_id, coordinates, or name/city combination.

  Uses unified DuplicateDetection module with distance-based similarity thresholds.
  GPS coordinates are prioritized for matching since venues exist at fixed physical locations.

  ## Matching Strategy
  1. place_id (if available) - exact match
  2. GPS coordinates + name (if available) - uses DuplicateDetection with distance-based thresholds
  3. Name only - fuzzy match using PostgreSQL trigram similarity
  """
  def find_existing_venue(%{place_id: place_id}) when not is_nil(place_id) do
    Repo.get_by(Venue, place_id: place_id)
  end

  # GPS-based matching using unified DuplicateDetection
  def find_existing_venue(%{latitude: lat, longitude: lng, city_id: city_id, name: name})
      when not is_nil(lat) and not is_nil(lng) and not is_nil(city_id) and not is_nil(name) do
    # Use unified duplicate detection with distance-based similarity thresholds
    case DuplicateDetection.find_duplicate(%{
           latitude: lat,
           longitude: lng,
           city_id: city_id,
           name: name
         }) do
      nil ->
        # No GPS-based match, fall back to name-based search
        find_existing_venue(%{name: name, city_id: city_id})

      venue ->
        similarity = DuplicateDetection.calculate_name_similarity(venue.name, name)

        Logger.info(
          "🏛️📍 Found venue by GPS+similarity: '#{venue.name}' for '#{name}' " <>
            "(#{Float.round(venue.distance, 1)}m away, #{Float.round(similarity * 100, 1)}% similar, ID: #{venue.id})"
        )

        # Convert map from PostGIS query to Venue struct
        Repo.get(Venue, venue.id)
    end
  end

  # Fallback to coordinates without name
  def find_existing_venue(%{latitude: lat, longitude: lng, city_id: city_id} = attrs)
      when not is_nil(lat) and not is_nil(lng) and not is_nil(city_id) do
    # If name is available, use it for better matching
    if Map.has_key?(attrs, :name) and not is_nil(attrs.name) do
      find_existing_venue(%{latitude: lat, longitude: lng, city_id: city_id, name: attrs.name})
    else
      # No name available - find closest venue within 50m
      # This is a fallback for cases where we only have coordinates
      nearby = DuplicateDetection.find_nearby_venues_postgis(lat, lng, city_id, 50)

      case nearby do
        [closest | _] ->
          Logger.info(
            "🏛️📍 Found venue by GPS only (no name): '#{closest.name}' at (#{lat}, #{lng}), " <>
              "#{Float.round(closest.distance, 1)}m away, ID: #{closest.id}"
          )

          Repo.get(Venue, closest.id)

        [] ->
          nil
      end
    end
  end

  # Name-only matching fallback
  def find_existing_venue(%{name: name, city_id: city_id}) when not is_nil(city_id) do
    # Clean UTF-8 before any database operations
    clean_name = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name)

    # First try exact match
    exact_match =
      from(v in Venue,
        where: v.name == ^clean_name and v.city_id == ^city_id,
        limit: 1
      )
      |> Repo.one()

    # If no exact match, try fuzzy match using PostgreSQL similarity
    if is_nil(exact_match) do
      fuzzy_match =
        from(v in Venue,
          where: v.city_id == ^city_id,
          where:
            fragment("similarity(?, ?) > ?", v.name, ^clean_name, ^@postgres_similarity_threshold),
          order_by: [desc: fragment("similarity(?, ?)", v.name, ^clean_name)],
          limit: 1
        )
        |> Repo.one()

      if fuzzy_match do
        similarity = DuplicateDetection.calculate_name_similarity(fuzzy_match.name, clean_name)

        Logger.info(
          "🏛️ Using similar venue (name only): '#{fuzzy_match.name}' for '#{clean_name}' " <>
            "(#{Float.round(similarity * 100, 1)}% similar, ID: #{fuzzy_match.id})"
        )

        fuzzy_match
      else
        nil
      end
    else
      exact_match
    end
  end

  def find_existing_venue(_), do: nil

  # Detects if a changeset error is due to unique constraint violation on place_id
  # Used to handle TOCTOU race conditions where multiple workers try to insert the same venue
  # Currently unused but kept for future race condition handling
  defp _has_place_id_constraint_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:place_id, {_msg, [constraint: :unique, constraint_name: "venues_place_id_unique_index"]}} ->
        true

      _ ->
        false
    end)
  end

  defp normalize_venue_data(data) do
    # Normalize the venue name and clean UTF-8 after normalization
    # Normalizer.normalize_text can corrupt UTF-8 with its regex operations
    raw_name = data[:name] || data["name"]

    normalized_name =
      if raw_name do
        raw_name
        |> Normalizer.normalize_text()
        |> EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8()
      else
        nil
      end

    normalized = %{
      name: normalized_name,
      address: data[:address] || data["address"],
      city_name: data[:city] || data["city"],
      state: data[:state] || data["state"],
      country_name: data[:country] || data["country"],
      latitude: parse_coordinate(data[:latitude] || data["latitude"]),
      longitude: parse_coordinate(data[:longitude] || data["longitude"]),
      place_id: data[:place_id] || data["place_id"]
    }

    if normalized.name do
      {:ok, normalized}
    else
      {:error, "Venue name is required"}
    end
  end

  defp parse_coordinate(nil), do: nil
  defp parse_coordinate(coord) when is_float(coord), do: coord
  defp parse_coordinate(coord) when is_integer(coord), do: coord / 1.0

  defp parse_coordinate(coord) when is_binary(coord) do
    case Float.parse(coord) do
      {value, _} -> value
      :error -> nil
    end
  end

  defp ensure_city(%{city_name: nil}), do: {:error, "City is required"}

  defp ensure_city(%{city_name: city_name, country_name: country_name} = data) do
    country = find_or_create_country(country_name)

    # If we couldn't resolve the country, we can't proceed
    if country == nil do
      {:error,
       "Cannot process city '#{city_name}' without a valid country. Unknown country: '#{country_name}'"}
    else
      # First try to find by exact name match
      city =
        from(c in City,
          where: c.name == ^city_name and c.country_id == ^country.id,
          limit: 1
        )
        |> Repo.one()

      # If not found, try to find by slug to handle variations (e.g., Kraków vs Krakow)
      city =
        city ||
          from(c in City,
            where: c.slug == ^Normalizer.create_slug(city_name) and c.country_id == ^country.id,
            limit: 1
          )
          |> Repo.one()

      # If still not found, check alternate names (e.g., "Warszawa" matches city with name "Warsaw")
      city =
        city ||
          from(c in City,
            where: c.country_id == ^country.id,
            where: fragment("? = ANY(?)", ^city_name, c.alternate_names),
            limit: 1
          )
          |> Repo.one()

      # If still not found, create it
      city = city || create_city(city_name, country, data)

      if city do
        # Schedule coordinate calculation if city has no coordinates
        # This ensures all cities get coordinates calculated from their venues
        # CityCoordinateCalculationJob handles deduplication (max once per 24h)
        if is_nil(city.latitude) || is_nil(city.longitude) do
          schedule_city_coordinate_update(city.id)
        end

        {:ok, city}
      else
        {:error, "Failed to find or create city: #{city_name}"}
      end
    end
  end

  defp find_or_create_country(country_name) do
    slug = Normalizer.create_slug(country_name)
    code = derive_country_code(country_name)

    # First try to find existing country by code (most reliable)
    existing_country =
      if code do
        Repo.get_by(Country, code: code)
      else
        nil
      end

    # If not found by code, try by slug
    existing_country = existing_country || Repo.get_by(Country, slug: slug)

    # If still not found and we have a valid code, create new country
    # If we don't have a valid code, we should NOT create a country with nil code
    if existing_country do
      existing_country
    else
      if code do
        create_country(country_name, code, slug)
      else
        # Log error and return nil - we can't create a country without a valid code
        Logger.error("Cannot create country '#{country_name}' without a valid ISO code")
        nil
      end
    end
  end

  defp create_country(name, code, slug) do
    changeset =
      %Country{}
      |> Country.changeset(%{
        name: name,
        code: code,
        slug: slug
      })

    case Repo.insert(changeset) do
      {:ok, country} ->
        country

      {:error, changeset} ->
        # Check if it's a unique constraint violation
        if has_country_constraint_error?(changeset) do
          # Another worker created it, fetch and return
          Logger.info("Country '#{name}' (#{code}) already exists, fetching existing record")
          Repo.get_by(Country, code: code) || Repo.get_by(Country, slug: slug)
        else
          # Some other error, log and return nil
          Logger.error("Failed to create country '#{name}': #{inspect(changeset.errors)}")
          nil
        end
    end
  end

  defp has_country_constraint_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:code, {_msg, [constraint: :unique, constraint_name: "countries_code_index"]}} ->
        true

      _ ->
        false
    end)
  end

  defp derive_country_code(country_name) when is_binary(country_name) do
    # Use CountryResolver which handles translations like "Polska" -> "Poland"
    case CountryResolver.resolve(country_name) do
      nil ->
        Logger.warning("Unknown country: #{country_name}, defaulting to nil")
        nil

      country ->
        country.alpha2
    end
  end

  defp derive_country_code(_), do: nil

  # SAFETY NET: Validate city name before creating city record
  # Allow nil city names - better to have event without city than pollute database
  defp create_city(nil, _country, _data), do: nil

  # This is Layer 2 of defense in depth - prevents ANY garbage from entering database
  # even if transformers forget validation or have bugs
  defp create_city(name, country, data) when not is_nil(name) do
    # Validate city name BEFORE database insertion
    case CityResolver.validate_city_name(name) do
      {:ok, validated_name} ->
        # Valid city name - proceed with creation
        attrs = %{
          name: validated_name,
          slug: Normalizer.create_slug(validated_name),
          country_id: country.id,
          latitude: data[:latitude],
          longitude: data[:longitude]
        }

        case %City{} |> City.changeset(attrs) |> Repo.insert() do
          {:ok, city} ->
            city

          {:error, changeset} ->
            # If insert fails (e.g., unique constraint), try to find the existing city
            # This handles race conditions and edge cases with slug generation
            Logger.warning(
              "Failed to create city #{validated_name}: #{inspect(changeset.errors)}"
            )

            from(c in City,
              where:
                c.country_id == ^country.id and
                  (c.name == ^validated_name or c.slug == ^attrs.slug),
              limit: 1
            )
            |> Repo.one()
            |> case do
              nil ->
                # If we still can't find it, something is wrong
                Logger.error(
                  "Cannot create or find city #{validated_name} in country #{country.name}"
                )

                nil

              city ->
                city
            end
        end

      {:error, reason} ->
        # REJECT invalid city name (postcode, street address, numeric value, etc.)
        Logger.error("""
        ❌ VenueProcessor REJECTED invalid city name (Layer 2 safety net):
        City name: #{inspect(name)}
        Country: #{country.name}
        Reason: #{reason}
        Source transformer must provide valid city name or nil.
        This prevents database pollution.
        """)

        # Return nil - this causes venue/event creation to fail (correct behavior)
        nil
    end
  end

  defp find_or_create_venue(data, city, source, source_scraper) do
    # Clean UTF-8 before creating venue attributes
    venue_attrs = %{
      name: EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(data.name),
      city_id: city.id,
      place_id: data.place_id,
      latitude: data.latitude,
      longitude: data.longitude
    }

    case find_existing_venue(venue_attrs) do
      nil ->
        create_venue(data, city, source, source_scraper)

      existing ->
        maybe_update_venue(existing, data, source_scraper)
    end
  end

  # Geocodes venue address using multi-provider system (Mapbox, HERE, Geoapify, etc.)
  # Returns {latitude, longitude, address, geocoding_metadata} tuple
  defp geocode_venue_address(data, city) do
    # Build full address: "Venue Name, Address, City, Country"
    full_address = build_full_address(data, city)

    Logger.info("🔍 Geocoding venue address: #{full_address}")

    case AddressGeocoder.geocode_address_with_metadata(full_address) do
      {:ok,
       %{
         city: _city_name,
         country: _country_name,
         latitude: lat,
         longitude: lng,
         address: address,
         geocoding_metadata: metadata
       }} ->
        Logger.info(
          "🗺️ ✅ Successfully geocoded venue '#{data.name}' via #{metadata.provider}: #{lat}, #{lng}, address: #{address}"
        )

        {lat, lng, address, metadata}

      {:error, reason, metadata} ->
        Logger.error(
          "🗺️ ❌ Failed to geocode venue '#{EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(data.name)}': #{reason}. " <>
            "Attempted providers: #{inspect(metadata.attempted_providers)}"
        )

        {nil, nil, nil, metadata}
    end
  end

  # Reverse geocodes coordinates to get address
  # Used when scrapers provide coordinates but no address (e.g., Resident Advisor)
  # Returns {address, metadata} tuple with geocoding provider information
  defp reverse_geocode_coordinates(lat, lng, city) when is_number(lat) and is_number(lng) do
    Logger.info("🔄 Reverse geocoding coordinates: #{lat}, #{lng}")

    # Try providers that support reverse geocoding in priority order
    providers_with_reverse = [
      EventasaurusDiscovery.Geocoding.Providers.Mapbox,
      EventasaurusDiscovery.Geocoding.Providers.HERE,
      EventasaurusDiscovery.Geocoding.Providers.Geoapify,
      EventasaurusDiscovery.Geocoding.Providers.GooglePlaces,
      EventasaurusDiscovery.Geocoding.Providers.LocationIQ,
      EventasaurusDiscovery.Geocoding.Providers.OpenStreetMap,
      EventasaurusDiscovery.Geocoding.Providers.Photon,
      EventasaurusDiscovery.Geocoding.Providers.Foursquare
    ]

    result = try_reverse_geocoding(providers_with_reverse, lat, lng, city, [])

    case result do
      {:ok, address, provider_name, attempted_providers} ->
        Logger.info(
          "🗺️ ✅ Successfully reverse geocoded to address: #{address} using #{provider_name}"
        )

        # Build metadata for reverse geocoding
        metadata = %{
          provider: provider_name,
          geocoded_at: DateTime.utc_now(),
          attempts: length(attempted_providers),
          attempted_providers: attempted_providers,
          # Reverse geocoding typically free
          cost_per_call: 0.0,
          collection_mode: true
        }

        {address, metadata}

      {:error, reason, attempted_providers} ->
        Logger.error(
          "🗺️ ❌ Failed to reverse geocode coordinates #{lat}, #{lng}: #{reason}. Tried: #{inspect(attempted_providers)}"
        )

        {nil, nil}
    end
  end

  defp reverse_geocode_coordinates(_lat, _lng, _city), do: {nil, nil}

  # Try reverse geocoding with multiple providers until one succeeds
  # Returns {:ok, address, provider_name, attempted_providers} or {:error, reason, attempted_providers}
  defp try_reverse_geocoding([], _lat, _lng, _city, attempted_providers) do
    {:error, :all_providers_failed, Enum.reverse(attempted_providers)}
  end

  defp try_reverse_geocoding([provider | rest], lat, lng, city, attempted_providers) do
    provider_name = provider_module_to_snake_case(provider)
    display_name = provider_module_to_name(provider)
    Logger.debug("🔍 Trying reverse geocoding with #{display_name}")

    updated_attempted = [provider_name | attempted_providers]

    try do
      case provider.search_by_coordinates(lat, lng) do
        {:ok, address} when is_binary(address) ->
          Logger.info("✅ #{display_name} reverse geocoding successful")
          {:ok, address, provider_name, Enum.reverse(updated_attempted)}

        {:error, _reason} ->
          Logger.debug("❌ #{display_name} reverse geocoding failed, trying next provider")
          try_reverse_geocoding(rest, lat, lng, city, updated_attempted)

        _other ->
          Logger.warning("⚠️ #{display_name} returned unexpected response, trying next provider")
          try_reverse_geocoding(rest, lat, lng, city, updated_attempted)
      end
    rescue
      error ->
        Logger.error("❌ #{display_name} raised error: #{inspect(error)}, trying next provider")
        try_reverse_geocoding(rest, lat, lng, city, updated_attempted)
    end
  end

  # Convert provider module to snake_case for database storage
  # Explicit mapping ensures consistent IDs across system
  defp provider_module_to_snake_case(module) do
    case module |> Module.split() |> List.last() do
      "OpenStreetMap" -> "openstreetmap"
      "GooglePlaces" -> "google_places"
      "LocationIQ" -> "locationiq"
      other -> other |> Macro.underscore()
    end
  end

  # Convert provider module to friendly name for logging
  defp provider_module_to_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> case do
      "GooglePlaces" -> "Google Places"
      "OpenStreetMap" -> "OpenStreetMap"
      "LocationIQ" -> "LocationIQ"
      name -> name
    end
  end

  # Builds full address string for geocoding
  defp build_full_address(data, city) do
    parts =
      [
        data.name,
        data.address,
        city.name,
        data.country_name
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    parts
  end

  # Extracts provider_ids map from geocoding metadata
  # The Orchestrator returns provider_ids in the result, which gets passed through
  # the geocoding_metadata field in AddressGeocoder
  defp extract_provider_ids_from_metadata(nil), do: %{}

  defp extract_provider_ids_from_metadata(metadata) when is_map(metadata) do
    # Support both atom and string keys from orchestrator/JSON
    case Map.get(metadata, :provider_ids) || Map.get(metadata, "provider_ids") do
      provider_ids when is_map(provider_ids) and map_size(provider_ids) > 0 ->
        provider_ids

      _ ->
        # Fallback: build from place_id and provider for backwards compatibility
        provider_name = Map.get(metadata, :provider) || Map.get(metadata, "provider")
        place_id = Map.get(metadata, :place_id) || Map.get(metadata, "place_id")

        if provider_name && place_id do
          %{provider_name => place_id}
        else
          %{}
        end
    end
  end

  defp create_venue(data, city, _source, source_scraper) do
    Logger.error("🔍 ENTER create_venue: name='#{data.name}', scraper=#{source_scraper}, has_coords=#{not is_nil(data.latitude)}")

    # Check if we need to geocode the venue address
    {latitude, longitude, geocoded_address, geocoding_metadata, geocoding_place_id, provider_ids} =
      if is_nil(data.latitude) || is_nil(data.longitude) do
        # Case 1: No coordinates provided → forward geocode (address → coordinates + address)
        {lat, lng, address, metadata} = geocode_venue_address(data, city)
        # Extract place_id and provider_ids from geocoding metadata if available
        place_id = if metadata, do: Map.get(metadata, :place_id), else: nil
        provider_ids_map = extract_provider_ids_from_metadata(metadata)
        {lat, lng, address, metadata, place_id, provider_ids_map}
      else
        # Case 2: Has coordinates
        if is_nil(data.address) do
          # Case 2a: Has coordinates but no address → reverse geocode (coordinates → address)
          # This handles Resident Advisor and similar scrapers
          {address, reverse_metadata} =
            reverse_geocode_coordinates(data.latitude, data.longitude, city)

          {data.latitude, data.longitude, address, reverse_metadata, nil, %{}}
        else
          # Case 2b: Has both coordinates and address → use them directly
          {data.latitude, data.longitude, nil, nil, nil, %{}}
        end
      end

    # Validate scraped name against geocoded name to prevent bad venue names
    # This uses VenueNameValidator to compare scraped vs geocoded names
    final_name = validate_and_choose_venue_name(data.name, geocoding_metadata, source_scraper)

    # Prefer geocoding provider's place_id over scraper's place_id
    final_place_id = geocoding_place_id || data.place_id

    Logger.error("🔍 CALL insert_venue_with_advisory_lock: name='#{final_name}', coords=(#{latitude}, #{longitude}), scraper=#{source_scraper}")

    # Insert venue with PostgreSQL advisory lock to prevent race conditions
    # This eliminates TOCTOU gaps by serializing inserts for the same location
    insert_venue_with_advisory_lock(
      data,
      city,
      final_name,
      final_place_id,
      latitude,
      longitude,
      geocoded_address,
      geocoding_metadata,
      source_scraper,
      provider_ids
    )
  end

  # Find existing venue by provider ID using GIN index
  # Uses the JSONB containment operator @> for efficient lookups
  # Currently unused but kept for future provider-based venue lookup
  defp _find_existing_venue_by_provider_id(provider_name, provider_id)
       when is_binary(provider_name) and is_binary(provider_id) do
    from(v in Venue,
      where: fragment("? @> ?", v.provider_ids, ^%{provider_name => provider_id}),
      limit: 1
    )
    |> Repo.one()
  end

  defp _find_existing_venue_by_provider_id(_, _), do: nil

  # Detects venue source from geocoding metadata
  # Returns the geocoding provider name (mapbox, google, geoapify, etc.)
  # or "scraper" if coordinates were provided directly
  defp detect_venue_source(geocoding_metadata) when is_map(geocoding_metadata) do
    # Use the provider from geocoding metadata
    Map.get(geocoding_metadata, :provider, "scraper")
  end

  defp detect_venue_source(_), do: "scraper"

  # Insert venue with PostgreSQL advisory lock to prevent TOCTOU race conditions
  #
  # Uses pg_advisory_xact_lock to serialize concurrent inserts of venues at the same location.
  # This prevents duplicate creation when multiple Oban workers process the same venue simultaneously.
  #
  # How it works:
  # 1. Round coordinates to ~50m grid to match duplicate detection threshold
  # 2. Generate lock key from (rounded_lat, rounded_lng, city_id)
  # 3. Acquire advisory lock (blocks other workers trying to insert at same location)
  # 4. Check one final time for duplicates (protected by lock)
  # 5. Insert if no duplicate found, or return existing venue
  # 6. Lock automatically released when transaction completes
  #
  # This eliminates the TOCTOU gap where two workers can both check for duplicates
  # before either commits, causing both to insert and create duplicates.
  defp insert_venue_with_advisory_lock(
         data,
         city,
         final_name,
         final_place_id,
         latitude,
         longitude,
         geocoded_address,
         geocoding_metadata,
         source_scraper,
         provider_ids
       ) do
    Logger.error("🔍 ENTER insert_venue_with_advisory_lock: name='#{final_name}', coords=(#{latitude}, #{longitude})")

    # Round coordinates to ~50m grid for lock key
    # This matches our duplicate detection threshold (<50m = same venue)
    lat_rounded = if latitude, do: Float.round(latitude, 3), else: 0.0
    lng_rounded = if longitude, do: Float.round(longitude, 3), else: 0.0

    # Generate lock key from GPS coordinates only (city-agnostic)
    # phash2 generates 32-bit integer suitable for pg_advisory_xact_lock
    # City assignment is subjective - GPS coordinates are objective
    lock_key = :erlang.phash2({lat_rounded, lng_rounded})

    Logger.error("🔍 Lock key=#{lock_key}, rounded=(#{lat_rounded}, #{lng_rounded}) [city-agnostic]")

    # Execute insert in transaction with advisory lock
    case Repo.transaction(fn ->
           # Acquire advisory lock for this location
           # Lock is held until transaction ends (commit or rollback)
           # Other workers trying to insert at same location will block here
           Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

           Logger.error(
             "🔒 Acquired advisory lock #{lock_key} for venue '#{final_name}' at (#{lat_rounded}, #{lng_rounded})"
           )

           # Now that we have the lock, do one final duplicate check
           # This is safe because no other worker can insert at this location until we're done
           Logger.error("🔍 Searching for duplicates: name='#{final_name}', coords=(#{latitude}, #{longitude}), city_id=#{city.id}")

           existing_venue =
             if latitude && longitude do
               find_existing_venue(%{
                 latitude: latitude,
                 longitude: longitude,
                 name: final_name,
                 city_id: city.id
               })
             else
               nil
             end

           Logger.error("🔍 Duplicate search result: #{if existing_venue, do: "FOUND ID #{existing_venue.id}", else: "NOT FOUND - will insert"}")

           if existing_venue do
             # Found duplicate while holding lock, return it
             Logger.error(
               "🏛️ ✅ DUPLICATE FOUND in locked transaction: '#{existing_venue.name}' (ID: #{existing_venue.id})"
             )

             existing_venue
           else
             # No duplicate found, safe to insert
             Logger.error("🔍 NO DUPLICATE - calling insert_new_venue for '#{final_name}'")

             case insert_new_venue(
                    data,
                    city,
                    final_name,
                    final_place_id,
                    latitude,
                    longitude,
                    geocoded_address,
                    geocoding_metadata,
                    source_scraper,
                    provider_ids
                  ) do
               {:ok, venue} ->
                 Logger.error("✅ INSERT SUCCESS: venue ID #{venue.id}, name='#{venue.name}'")
                 venue

               {:error, error} ->
                 Logger.error("❌ Insert failed in locked transaction: #{inspect(error)}, rolling back")
                 Repo.rollback(error)
             end
           end
         end) do
      {:ok, venue} ->
        {:ok, venue}

      {:error, error} ->
        {:error, error}
    end
  end

  defp insert_new_venue(
         data,
         city,
         final_name,
         final_place_id,
         latitude,
         longitude,
         geocoded_address,
         geocoding_metadata,
         source_scraper,
         provider_ids
       ) do
    # All discovery sources use "scraper" as the venue source
    # Clean UTF-8 for venue name before database insert

    # Build geocoding metadata based on the geocoding path taken
    final_geocoding_metadata =
      cond do
        # Multi-provider geocoding was used (from geocode_venue_address)
        geocoding_metadata != nil ->
          geocoding_metadata
          |> MetadataBuilder.add_scraper_source(source_scraper)

        # AddressGeocoder was used directly by scraper (Question One pattern)
        Map.has_key?(data, :geocoding_metadata) ->
          data.geocoding_metadata
          |> MetadataBuilder.add_scraper_source(source_scraper)

        # Coordinates provided directly by scraper (no geocoding needed)
        latitude != nil and longitude != nil ->
          MetadataBuilder.build_provided_coordinates_metadata()
          |> MetadataBuilder.add_scraper_source(source_scraper)

        # No coordinates available - deferred geocoding (Karnet pattern)
        true ->
          MetadataBuilder.build_deferred_geocoding_metadata()
          |> MetadataBuilder.add_scraper_source(source_scraper)
      end

    # Auto-detect source from geocoding metadata
    # Use the geocoding provider name (mapbox, google, geoapify, etc.)
    # Falls back to "scraper" for venues with provided coordinates
    source = detect_venue_source(geocoding_metadata)

    # Override for provided coordinates to distinguish from scraped venues
    source =
      if source == "scraper" && final_geocoding_metadata[:provider] == "provided" do
        "provided"
      else
        source
      end

    # Validate and clean source_scraper (prevent empty strings in database)
    valid_source_scraper =
      cond do
        is_binary(source_scraper) && String.trim(source_scraper) != "" ->
          source_scraper

        true ->
          Logger.warning("⚠️ Missing source_scraper for venue processing, using fallback")
          # Explicit fallback instead of nil
          "unknown_scraper"
      end

    # Build geocoding_performance for dashboard (flat structure)
    # This should be populated for ALL venues, including those with provided coordinates
    geocoding_performance =
      if geocoding_metadata do
        # Venue was geocoded using multi-provider system
        geocoding_metadata
        |> Map.put(:source_scraper, valid_source_scraper)
        |> Map.put(:cost_per_call, Map.get(geocoding_metadata, :cost_per_call, 0.0))
      else
        # Venue has provided coordinates (no geocoding needed)
        # Build performance data from final_geocoding_metadata
        if final_geocoding_metadata && final_geocoding_metadata[:provider] == "provided" do
          %{
            provider: "provided",
            source_scraper: valid_source_scraper,
            geocoded_at: final_geocoding_metadata[:geocoded_at] || DateTime.utc_now(),
            cost_per_call: 0.0,
            attempts: 0,
            attempted_providers: []
          }
        else
          nil
        end
      end

    # Priority: scraper address > geocoded address
    # This ensures we use the scraper's address if provided,
    # and fall back to the geocoded address if not
    final_address = data.address || geocoded_address

    attrs = %{
      name: EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(final_name),
      address: final_address,
      city: city.name,
      state: data.state,
      country: data.country_name,
      latitude: latitude,
      longitude: longitude,
      venue_type: "venue",
      place_id: final_place_id,
      source: source,
      city_id: city.id,
      provider_ids: provider_ids,
      geocoding_performance: geocoding_performance,
      metadata: %{
        geocoding: final_geocoding_metadata,
        geocoding_metadata: geocoding_metadata
      }
    }

    case Venue.changeset(%Venue{}, attrs) |> Repo.insert() do
      {:ok, venue} ->
        {:ok, venue}

      {:error, changeset} ->
        # Check if error is due to duplicate venue detection (not a real error)
        # If so, find and return the existing venue instead of failing
        if has_duplicate_venue_error?(changeset) do
          # Extract the duplicate venue info from structured error opts
          # This is more reliable than regex parsing and handles edge cases better
          duplicate_venue =
            changeset.errors
            |> Keyword.get_values(:base)
            |> Enum.find_value(fn {_msg, opts} ->
              case Keyword.get(opts, :existing_id) do
                id when is_integer(id) -> Repo.get(Venue, id)
                _ -> nil
              end
            end)

          if duplicate_venue do
            Logger.info(
              "🏛️ ✅ Found existing venue via duplicate detection: '#{duplicate_venue.name}' (ID: #{duplicate_venue.id})"
            )

            {:ok, duplicate_venue}
          else
            # Couldn't extract venue ID from opts - log and propagate error
            errors = format_changeset_errors(changeset)

            Logger.error(
              "❌ Duplicate detected but couldn't find existing venue for '#{EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(data.name)}': #{errors}"
            )

            {:error, "Failed to create venue: #{errors}"}
          end
        else
          # Some other error (GPS coordinates, validation, etc.)
          errors = format_changeset_errors(changeset)

          Logger.error(
            "❌ Failed to create venue '#{EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(data.name)}': #{errors}"
          )

          # If it's specifically a GPS coordinate error, provide clear message for Oban
          if has_coordinate_errors?(changeset) do
            {:error,
             "GPS coordinates required but unavailable for venue '#{EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(data.name)}' in #{city.name}. Geocoding failed or returned no results."}
          else
            {:error, "Failed to create venue: #{errors}"}
          end
        end
    end
  end

  defp maybe_update_venue(venue, data, _source_scraper) do
    updates = []

    # Note: place_id field was removed from venues table
    # Google Places IDs are now stored in provider_ids map
    updates =
      if data[:place_id] && !Map.has_key?(venue.provider_ids || %{}, "google_places") do
        current_provider_ids = venue.provider_ids || %{}
        updated_provider_ids = Map.put(current_provider_ids, "google_places", data.place_id)
        [{:provider_ids, updated_provider_ids} | updates]
      else
        updates
      end

    # Check if we need to geocode or use provided coordinates
    updates =
      if is_nil(venue.latitude) || is_nil(venue.longitude) do
        if data.latitude && data.longitude do
          # Use provided coordinates
          [{:latitude, data.latitude}, {:longitude, data.longitude} | updates]
        else
          # Try to geocode using multi-provider system
          lookup_data = %{
            name: venue.name,
            address: venue.address || data.address,
            city_name: venue.city,
            state: venue.state || data.state,
            country_name: venue.country || data.country_name
          }

          # Create a minimal city struct for geocoding
          city_for_lookup = %{
            name: venue.city,
            country: %{name: venue.country || data.country_name}
          }

          case geocode_venue_address(lookup_data, city_for_lookup) do
            {lat, lng, address, _metadata} when not is_nil(lat) and not is_nil(lng) ->
              Logger.info("🗺️ Successfully geocoded existing venue '#{venue.name}'")

              # Update with coordinates and address (if address is nil on venue and we got one from geocoding)
              updates_with_coords = [{:latitude, lat}, {:longitude, lng} | updates]

              if is_nil(venue.address) && address do
                [{:address, address} | updates_with_coords]
              else
                updates_with_coords
              end

            _ ->
              Logger.error(
                "🗺️❌ Cannot update venue '#{venue.name}' without GPS coordinates: Multi-provider geocoding failed"
              )

              # Return error immediately if we can't get coordinates
              # This will prevent the venue from being updated without required coordinates
              {:error,
               "GPS coordinates required but unavailable for venue '#{venue.name}'. Multi-provider geocoding failed."}
          end
        end
      else
        updates
      end

    # Only proceed with updates if we didn't encounter an error above
    case updates do
      {:error, _} = error ->
        error

      _ ->
        updates =
          if is_nil(venue.address) && data.address do
            [{:address, data.address} | updates]
          else
            updates
          end

        if Enum.any?(updates) do
          case Venue.changeset(venue, Map.new(updates)) |> Repo.update() do
            {:ok, venue} ->
              {:ok, venue}

            {:error, changeset} ->
              errors = format_changeset_errors(changeset)
              Logger.error("❌ Failed to update venue '#{venue.name}': #{errors}")
              {:error, "Failed to update venue: #{errors}"}
          end
        else
          {:ok, venue}
        end
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      # Safe substitution without atom conversion
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end

  defp has_coordinate_errors?(changeset) do
    errors = changeset.errors

    Enum.any?(errors, fn {field, _} ->
      field in [:latitude, :longitude]
    end)
  end

  # Detects if a changeset error is due to duplicate venue detection
  # Duplicate errors are added to :base field with "Duplicate venue found:" prefix
  defp has_duplicate_venue_error?(changeset) do
    base_errors = Keyword.get_values(changeset.errors, :base)

    Enum.any?(base_errors, fn {error_msg, _} ->
      String.contains?(error_msg, "Duplicate venue found:")
    end)
  end

  defp schedule_city_coordinate_update(city_id) do
    # Schedule coordinate calculation job for this city
    # Job will check internally if update is needed (24hr deduplication)
    EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob.schedule_update(city_id)
    :ok
  rescue
    error ->
      Logger.warning(
        "Failed to schedule coordinate update for city #{city_id}: #{inspect(error)}"
      )

      # Don't fail the main venue processing if coordinate scheduling fails
      :ok
  end

  # Validates venue name using VenueNameValidator and returns the best name to use
  # This prevents bad venue names (UI elements, image captions) from entering the database
  defp validate_and_choose_venue_name(scraped_name, geocoding_metadata, source_scraper) do
    # Build metadata structure expected by VenueNameValidator
    # VenueNameValidator expects: %{"geocoding_metadata" => geocoding_metadata}
    # AddressGeocoder returns atom-keyed maps, but VenueNameValidator expects string keys
    # (since it's designed for JSON-persisted data). Normalize via JSON round-trip.
    metadata =
      %{
        "geocoding_metadata" =>
          case geocoding_metadata do
            nil -> %{}
            data -> data |> Jason.encode!() |> Jason.decode!()
          end
      }

    case VenueNameValidator.choose_name(scraped_name, metadata) do
      {:ok, chosen_name, :scraped_validated} ->
        # Scraped name validated as good quality (similarity >= 0.7)
        Logger.debug("🏛️ ✅ Venue name validated: '#{scraped_name}' (scraper: #{source_scraper})")

        chosen_name

      {:ok, chosen_name, :geocoded_moderate_diff, similarity} ->
        # Moderate difference - using geocoded name
        Logger.info(
          "🏛️ ⚠️ Using geocoded name: '#{chosen_name}' instead of '#{scraped_name}' " <>
            "(similarity: #{Float.round(similarity * 100, 1)}%, scraper: #{source_scraper})"
        )

        chosen_name

      {:ok, chosen_name, :geocoded_low_similarity, similarity} ->
        # Very different - strongly preferring geocoded name
        Logger.warning(
          "🏛️ 🔴 Replacing bad venue name: '#{scraped_name}' → '#{chosen_name}' " <>
            "(similarity: #{Float.round(similarity * 100, 1)}%, scraper: #{source_scraper})"
        )

        chosen_name

      {:warning, scraped_name, :no_geocoded_name} ->
        # No geocoded name available - use scraped and log warning
        Logger.debug(
          "🏛️ ℹ️ No geocoded name available, using scraped: '#{scraped_name}' (scraper: #{source_scraper})"
        )

        scraped_name
    end
  end
end
