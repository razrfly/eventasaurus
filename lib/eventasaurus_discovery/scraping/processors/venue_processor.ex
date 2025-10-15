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
  alias EventasaurusDiscovery.Locations.{City, Country, CountryResolver}
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer
  alias EventasaurusDiscovery.Helpers.{CityResolver, AddressGeocoder}
  alias EventasaurusDiscovery.Geocoding.MetadataBuilder

  import Ecto.Query
  require Logger

  # ========================================
  # Venue Matching Configuration
  # ========================================
  # These thresholds control how aggressively we match venues to prevent duplicates.
  # Higher GPS radius and lower similarity thresholds = more aggressive matching (fewer duplicates, more false positives)
  # Lower GPS radius and higher similarity thresholds = less aggressive matching (more duplicates, fewer false positives)

  # GPS-based matching thresholds (in meters)
  @gps_tight_radius_meters 50
  # Increased from 100m to catch venues across street
  @gps_broad_radius_meters 200

  # Name similarity thresholds (0.0 = completely different, 1.0 = identical)
  # Uses Jaro distance algorithm: https://en.wikipedia.org/wiki/Jaro%E2%80%93Winkler_distance
  # Very low threshold for tight GPS matches (venues at same coords)
  @name_similarity_tight_gps 0.2
  # Medium threshold for broader GPS matches (within 200m)
  @name_similarity_broad_gps 0.5

  # PostgreSQL similarity() function threshold (uses trigram matching)
  # This is different from Jaro distance - uses character n-grams
  # Lowered from 0.7 to 0.6 to catch more variants (e.g., "Kino Cinema" vs "Cinema Hall")
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
  GPS coordinates are prioritized for matching since venues exist at fixed physical locations.
  """
  def find_existing_venue(%{place_id: place_id}) when not is_nil(place_id) do
    Repo.get_by(Venue, place_id: place_id)
  end

  # GPS-based matching with relaxed name similarity
  def find_existing_venue(%{latitude: lat, longitude: lng, city_id: city_id, name: name})
      when not is_nil(lat) and not is_nil(lng) and not is_nil(city_id) and not is_nil(name) do
    # First try tight GPS matching
    gps_match = find_venue_by_coordinates(lat, lng, city_id, @gps_tight_radius_meters)

    case gps_match do
      nil ->
        # No GPS match, try broader search then fall back to name-based
        broader_match = find_venue_by_coordinates(lat, lng, city_id, @gps_broad_radius_meters)

        if broader_match do
          # Check name similarity for broader GPS match
          similarity = calculate_similarity(broader_match.name, name)

          if similarity > @name_similarity_broad_gps do
            Logger.info(
              "🏛️📍 Found venue by GPS (#{@gps_broad_radius_meters}m): '#{broader_match.name}' for '#{name}' (similarity: #{similarity})"
            )

            broader_match
          else
            # GPS match but names too different, fall back to name search
            find_existing_venue(%{name: name, city_id: city_id})
          end
        else
          # No GPS match at all, use name-based search
          find_existing_venue(%{name: name, city_id: city_id})
        end

      venue ->
        # Found within tight radius - verify with very relaxed name similarity
        similarity = calculate_similarity(venue.name, name)

        if similarity > @name_similarity_tight_gps do
          Logger.info(
            "🏛️📍 Found venue by GPS (#{@gps_tight_radius_meters}m): '#{venue.name}' for '#{name}' (GPS match, similarity: #{similarity})"
          )

          venue
        else
          # GPS matches but names are completely different - log warning but accept it
          Logger.warning(
            "🏛️⚠️ GPS match but very low name similarity: '#{venue.name}' vs '#{name}' (similarity: #{similarity})"
          )

          # Still return the GPS match as venues at same coordinates are likely the same
          venue
        end
    end
  end

  # Fallback to coordinates without name
  def find_existing_venue(%{latitude: lat, longitude: lng, city_id: city_id} = attrs)
      when not is_nil(lat) and not is_nil(lng) and not is_nil(city_id) do
    # Try coordinates (tight radius preferred, broad radius fallback)
    venue =
      find_venue_by_coordinates(lat, lng, city_id, @gps_tight_radius_meters) ||
        find_venue_by_coordinates(lat, lng, city_id, @gps_broad_radius_meters)

    # If no coordinate match, try by name if available
    if is_nil(venue) and Map.has_key?(attrs, :name) do
      find_existing_venue(%{name: attrs.name, city_id: city_id})
    else
      venue
    end
  end

  def find_existing_venue(%{name: name, city_id: city_id}) do
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
        Logger.info(
          "🏛️ Using similar venue: '#{fuzzy_match.name}' for '#{clean_name}' (PostgreSQL similarity > #{@postgres_similarity_threshold}, Jaro: #{calculate_similarity(fuzzy_match.name, clean_name)})"
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

  defp calculate_similarity(name1, name2) do
    # PostgreSQL boundary protection: clean UTF-8 before similarity calculation
    # Elixir's jaro_distance crashes on invalid UTF-8
    clean_name1 = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name1)
    clean_name2 = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name2)
    Float.round(String.jaro_distance(clean_name1, clean_name2), 2)
  end

  # Detects if a changeset error is due to unique constraint violation on place_id
  # Used to handle TOCTOU race conditions where multiple workers try to insert the same venue
  defp has_place_id_constraint_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:place_id, {_msg, [constraint: :unique, constraint_name: "venues_place_id_unique_index"]}} ->
        true

      _ ->
        false
    end)
  end

  defp find_venue_by_coordinates(lat, lng, city_id, radius_meters) do
    # Convert to float if needed
    lat_float =
      case lat do
        %Decimal{} -> Decimal.to_float(lat)
        val -> val
      end

    lng_float =
      case lng do
        %Decimal{} -> Decimal.to_float(lng)
        val -> val
      end

    # Simple distance calculation using degrees
    # At latitude ~50° (Kraków), 1 degree ≈ 111km, so 100m ≈ 0.0009 degrees
    lat_delta = radius_meters / 111_000.0
    lng_delta = radius_meters / (111_000.0 * :math.cos(lat_float * :math.pi() / 180))

    min_lat = lat_float - lat_delta
    max_lat = lat_float + lat_delta
    min_lng = lng_float - lng_delta
    max_lng = lng_float + lng_delta

    from(v in Venue,
      where:
        v.city_id == ^city_id and
          fragment("CAST(? AS float8) >= ?", v.latitude, ^min_lat) and
          fragment("CAST(? AS float8) <= ?", v.latitude, ^max_lat) and
          fragment("CAST(? AS float8) >= ?", v.longitude, ^min_lng) and
          fragment("CAST(? AS float8) <= ?", v.longitude, ^max_lng),
      limit: 1
    )
    |> Repo.one()
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
  # Returns {latitude, longitude, geocoding_metadata} tuple
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
         geocoding_metadata: metadata
       }} ->
        Logger.info(
          "🗺️ ✅ Successfully geocoded venue '#{data.name}' via #{metadata.provider}: #{lat}, #{lng}"
        )

        {lat, lng, metadata}

      {:error, reason, metadata} ->
        Logger.error(
          "🗺️ ❌ Failed to geocode venue '#{EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(data.name)}': #{reason}. " <>
            "Attempted providers: #{inspect(metadata.attempted_providers)}"
        )

        {nil, nil, metadata}
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

  defp create_venue(data, city, _source, source_scraper) do
    # Check if we need to geocode the venue address
    {latitude, longitude, geocoding_metadata, geocoding_place_id} =
      if is_nil(data.latitude) || is_nil(data.longitude) do
        # Try to geocode using multi-provider system
        {lat, lng, metadata} = geocode_venue_address(data, city)
        # Extract place_id from geocoding metadata if available
        place_id = if metadata, do: Map.get(metadata, :place_id), else: nil
        {lat, lng, metadata, place_id}
      else
        # Use provided coordinates
        {data.latitude, data.longitude, nil, nil}
      end

    # Use scraped name and place_id
    final_name = data.name
    # Prefer geocoding provider's place_id over scraper's place_id
    final_place_id = geocoding_place_id || data.place_id

    # RACE CONDITION FIX: Re-check if place_id now exists after geocoding
    # This prevents duplicates when multiple Oban workers geocode the same venue in parallel
    if final_place_id do
      case find_existing_venue(%{place_id: final_place_id}) do
        nil ->
          # Safe to insert, no existing venue with this place_id
          # However, another worker could still insert between the check and insert (TOCTOU gap)
          # The database unique constraint will catch this, so we handle constraint violations
          case insert_new_venue(
                 data,
                 city,
                 final_name,
                 final_place_id,
                 latitude,
                 longitude,
                 geocoding_metadata,
                 source_scraper
               ) do
            {:ok, venue} ->
              {:ok, venue}

            {:error, changeset} ->
              # Check if it's a unique constraint violation on place_id
              if has_place_id_constraint_error?(changeset) do
                # Another worker beat us to the insert, fetch and return the existing venue
                case find_existing_venue(%{place_id: final_place_id}) do
                  nil ->
                    # Unlikely: constraint fired but we can't find the venue
                    Logger.error(
                      "🏛️ ❌ Unique constraint violation but venue not found: place_id=#{final_place_id}"
                    )

                    {:error, changeset}

                  existing ->
                    Logger.info(
                      "🏛️ ✅ Resolved race condition via constraint: '#{existing.name}' (place_id: #{final_place_id})"
                    )

                    {:ok, existing}
                end
              else
                # Some other error, propagate it
                {:error, changeset}
              end
          end

        existing ->
          # Another worker just created it, return existing venue
          Logger.info(
            "🏛️ ✅ Found existing venue after geocoding: '#{existing.name}' (place_id: #{final_place_id})"
          )

          {:ok, existing}
      end
    else
      # No place_id, proceed with normal insert
      insert_new_venue(
        data,
        city,
        final_name,
        final_place_id,
        latitude,
        longitude,
        geocoding_metadata,
        source_scraper
      )
    end
  end

  # Detects venue source from geocoding metadata
  # Returns the geocoding provider name (mapbox, google, geoapify, etc.)
  # or "scraper" if coordinates were provided directly
  defp detect_venue_source(geocoding_metadata) when is_map(geocoding_metadata) do
    # Use the provider from geocoding metadata
    Map.get(geocoding_metadata, :provider, "scraper")
  end

  defp detect_venue_source(_), do: "scraper"

  defp insert_new_venue(
         data,
         city,
         final_name,
         final_place_id,
         latitude,
         longitude,
         geocoding_metadata,
         source_scraper
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

    attrs = %{
      name: EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(final_name),
      address: data.address,
      city: city.name,
      state: data.state,
      country: data.country_name,
      latitude: latitude,
      longitude: longitude,
      venue_type: "venue",
      place_id: final_place_id,
      source: source,
      city_id: city.id,
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

  defp maybe_update_venue(venue, data, _source_scraper) do
    updates = []

    updates =
      if is_nil(venue.place_id) && data.place_id do
        [{:place_id, data.place_id} | updates]
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
            {lat, lng, _metadata} when not is_nil(lat) and not is_nil(lng) ->
              Logger.info("🗺️ Successfully geocoded existing venue '#{venue.name}'")

              # Update with coordinates
              [{:latitude, lat}, {:longitude, lng} | updates]

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
end
