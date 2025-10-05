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
  alias EventasaurusWeb.Services.GooglePlaces.{TextSearch, Details, VenuePlacesAdapter}

  import Ecto.Query
  require Logger

  @doc """
  Processes venue data and returns a venue record.
  Creates or finds existing venue, city, and country as needed.
  """
  def process_venue(venue_data, source \\ "scraper") do
    # Data is already cleaned at HTTP client level (single entry point validation)
    with {:ok, normalized_data} <- normalize_venue_data(venue_data),
         {:ok, city} <- ensure_city(normalized_data),
         {:ok, venue} <- find_or_create_venue(normalized_data, city, source) do
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
    # First try tight GPS matching (within 50 meters)
    gps_match = find_venue_by_coordinates(lat, lng, city_id, 50)

    case gps_match do
      nil ->
        # No GPS match, try broader search (100m) then fall back to name-based
        broader_match = find_venue_by_coordinates(lat, lng, city_id, 100)

        if broader_match do
          # Check name similarity for broader GPS match
          similarity = calculate_similarity(broader_match.name, name)

          if similarity > 0.5 do
            Logger.info(
              "🏛️📍 Found venue by GPS (100m): '#{broader_match.name}' for '#{name}' (similarity: #{similarity})"
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
        # Found within 50 meters - verify with very relaxed name similarity (20%)
        similarity = calculate_similarity(venue.name, name)

        if similarity > 0.2 do
          Logger.info(
            "🏛️📍 Found venue by GPS (50m): '#{venue.name}' for '#{name}' (GPS match, similarity: #{similarity})"
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
    # Try coordinates (within 50 meters preferred, 100 meters fallback)
    venue =
      find_venue_by_coordinates(lat, lng, city_id, 50) ||
        find_venue_by_coordinates(lat, lng, city_id, 100)

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

    # If no exact match, try fuzzy match
    if is_nil(exact_match) do
      fuzzy_match =
        from(v in Venue,
          where: v.city_id == ^city_id,
          where: fragment("similarity(?, ?) > ?", v.name, ^clean_name, 0.7),
          order_by: [desc: fragment("similarity(?, ?)", v.name, ^clean_name)],
          limit: 1
        )
        |> Repo.one()

      if fuzzy_match do
        Logger.info(
          "🏛️ Using similar venue: '#{fuzzy_match.name}' for '#{clean_name}' (similarity: #{calculate_similarity(fuzzy_match.name, clean_name)})"
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
    %Country{}
    |> Country.changeset(%{
      name: name,
      code: code,
      slug: slug
    })
    |> Repo.insert!()
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

  defp create_city(name, country, data) do
    attrs = %{
      name: name,
      slug: Normalizer.create_slug(name),
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
        Logger.warning("Failed to create city #{name}: #{inspect(changeset.errors)}")

        from(c in City,
          where:
            c.country_id == ^country.id and
              (c.name == ^name or c.slug == ^attrs.slug),
          limit: 1
        )
        |> Repo.one()
        |> case do
          nil ->
            # If we still can't find it, something is wrong
            Logger.error("Cannot create or find city #{name} in country #{country.name}")
            nil

          city ->
            city
        end
    end
  end

  defp find_or_create_venue(data, city, source) do
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
        create_venue(data, city, source)

      existing ->
        maybe_update_venue(existing, data)
    end
  end

  # Looks up venue data from Google Places API using TextSearch + Details
  # Returns {latitude, longitude, google_name, google_place_id} tuple
  defp lookup_venue_from_google_places(data, city) do
    # Build search query: "Venue Name, City, Country"
    query = build_google_places_query(data, city)

    Logger.info("🔍 Looking up venue via Google Places: #{query}")

    with {:ok, [first_result | _]} <- TextSearch.search(query),
         place_id <- Map.get(first_result, "place_id"),
         {:ok, details} <- Details.fetch(place_id),
         venue_data <- VenuePlacesAdapter.extract_venue_data(details) do
      Logger.info(
        "🗺️ ✅ Found venue via Google Places: '#{venue_data.name}' (place_id: #{venue_data.place_id})"
      )

      # Return the full details map for metadata storage
      {venue_data.latitude, venue_data.longitude, venue_data.name, venue_data.place_id, details}
    else
      {:ok, []} ->
        Logger.warning("🗺️ ⚠️ No Google Places results for: #{query}")
        {nil, nil, nil, nil, nil}

      {:error, reason} ->
        Logger.error(
          "🗺️ ❌ Failed to lookup venue '#{EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(data.name)}' via Google Places: #{inspect(reason)}"
        )

        {nil, nil, nil, nil, nil}

      error ->
        Logger.error("🗺️ ❌ Unexpected error looking up venue via Google Places: #{inspect(error)}")

        {nil, nil, nil, nil, nil}
    end
  end

  # Builds Google Places search query from venue data
  defp build_google_places_query(data, city) do
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

  defp create_venue(data, city, _source) do
    # Check if we need to lookup venue data from Google Places
    {latitude, longitude, google_name, google_place_id, google_metadata} =
      if is_nil(data.latitude) || is_nil(data.longitude) do
        # Try to get venue data from Google Places API
        lookup_venue_from_google_places(data, city)
      else
        # Use provided coordinates
        {data.latitude, data.longitude, nil, nil, nil}
      end

    # Prefer Google's official venue name over scraped name when available
    final_name = google_name || data.name
    final_place_id = google_place_id || data.place_id

    # All discovery sources use "scraper" as the venue source
    # Clean UTF-8 for venue name before database insert
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
      source: "scraper",
      city_id: city.id,
      metadata: google_metadata
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

  defp maybe_update_venue(venue, data) do
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
          # Try to lookup from Google Places if we don't have coordinates from either source
          lookup_data = %{
            name: venue.name,
            address: venue.address || data.address,
            city_name: venue.city,
            state: venue.state || data.state,
            country_name: venue.country || data.country_name
          }

          # Create a minimal city struct for the lookup
          city_for_lookup = %{name: venue.city}

          case lookup_venue_from_google_places(lookup_data, city_for_lookup) do
            {lat, lng, google_name, google_place_id}
            when not is_nil(lat) and not is_nil(lng) ->
              Logger.info(
                "🗺️ Successfully looked up existing venue '#{venue.name}' via Google Places"
              )

              # Update with coordinates, and prefer Google's official name if available
              coord_updates = [{:latitude, lat}, {:longitude, lng}]

              coord_updates =
                if google_name && google_name != venue.name do
                  Logger.info("🗺️ Updating venue name '#{venue.name}' → '#{google_name}'")
                  [{:name, google_name} | coord_updates]
                else
                  coord_updates
                end

              coord_updates =
                if google_place_id && is_nil(venue.place_id) do
                  [{:place_id, google_place_id} | coord_updates]
                else
                  coord_updates
                end

              coord_updates ++ updates

            _ ->
              Logger.error(
                "🗺️❌ Cannot update venue '#{venue.name}' without GPS coordinates: Google Places lookup failed"
              )

              # Return error immediately if we can't get coordinates
              # This will prevent the venue from being updated without required coordinates
              {:error,
               "GPS coordinates required but unavailable for venue '#{venue.name}'. Google Places lookup failed."}
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
end
