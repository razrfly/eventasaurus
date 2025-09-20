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
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer

  import Ecto.Query
  require Logger

  @doc """
  Processes venue data and returns a venue record.
  Creates or finds existing venue, city, and country as needed.
  """
  def process_venue(venue_data, source \\ "scraper") do
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
            Logger.info("🏛️📍 Found venue by GPS (100m): '#{broader_match.name}' for '#{name}' (similarity: #{similarity})")
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
          Logger.info("🏛️📍 Found venue by GPS (50m): '#{venue.name}' for '#{name}' (GPS match, similarity: #{similarity})")
          venue
        else
          # GPS matches but names are completely different - log warning but accept it
          Logger.warning("🏛️⚠️ GPS match but very low name similarity: '#{venue.name}' vs '#{name}' (similarity: #{similarity})")
          # Still return the GPS match as venues at same coordinates are likely the same
          venue
        end
    end
  end

  # Fallback to coordinates without name
  def find_existing_venue(%{latitude: lat, longitude: lng, city_id: city_id} = attrs)
      when not is_nil(lat) and not is_nil(lng) and not is_nil(city_id) do
    # Try coordinates (within 50 meters preferred, 100 meters fallback)
    venue = find_venue_by_coordinates(lat, lng, city_id, 50) ||
            find_venue_by_coordinates(lat, lng, city_id, 100)

    # If no coordinate match, try by name if available
    if is_nil(venue) and Map.has_key?(attrs, :name) do
      find_existing_venue(%{name: attrs.name, city_id: city_id})
    else
      venue
    end
  end

  def find_existing_venue(%{name: name, city_id: city_id}) do
    # First try exact match
    exact_match = from(v in Venue,
      where: v.name == ^name and v.city_id == ^city_id,
      limit: 1
    )
    |> Repo.one()

    # If no exact match, try fuzzy match
    if is_nil(exact_match) do
      fuzzy_match = from(v in Venue,
        where: v.city_id == ^city_id,
        where: fragment("similarity(?, ?) > ?", v.name, ^name, 0.7),
        order_by: [desc: fragment("similarity(?, ?)", v.name, ^name)],
        limit: 1
      )
      |> Repo.one()

      if fuzzy_match do
        Logger.info("🏛️ Using similar venue: '#{fuzzy_match.name}' for '#{name}' (similarity: #{calculate_similarity(fuzzy_match.name, name)})")
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
    # Use Elixir's String.jaro_distance for logging
    Float.round(String.jaro_distance(name1, name2), 2)
  end

  defp find_venue_by_coordinates(lat, lng, city_id, radius_meters) do
    # Convert to float if needed
    lat_float = case lat do
      %Decimal{} -> Decimal.to_float(lat)
      val -> val
    end

    lng_float = case lng do
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
      where: v.city_id == ^city_id and
             fragment("CAST(? AS float8) >= ?", v.latitude, ^min_lat) and
             fragment("CAST(? AS float8) <= ?", v.latitude, ^max_lat) and
             fragment("CAST(? AS float8) >= ?", v.longitude, ^min_lng) and
             fragment("CAST(? AS float8) <= ?", v.longitude, ^max_lng),
      limit: 1
    )
    |> Repo.one()
  end

  defp normalize_venue_data(data) do
    normalized = %{
      name: Normalizer.normalize_text(data[:name] || data["name"]),
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

    # First try to find by exact name match
    city = from(c in City,
      where: c.name == ^city_name and c.country_id == ^country.id,
      limit: 1
    )
    |> Repo.one()

    # If not found, try to find by slug to handle variations (e.g., Kraków vs Krakow)
    city = city || from(c in City,
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

  defp find_or_create_country(country_name) do
    slug = Normalizer.create_slug(country_name)
    code = derive_country_code(country_name)

    Repo.get_by(Country, slug: slug) ||
      create_country(country_name, code, slug)
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
    # Use Countries library to get proper country code
    case find_country_by_name(country_name) do
      nil ->
        Logger.warning("Unknown country: #{country_name}, using XX")
        "XX"
      country ->
        country.alpha2
    end
  end
  defp derive_country_code(_), do: "XX"

  defp find_country_by_name(name) when is_binary(name) do
    input = String.trim(name)

    # Try as country code first
    country = if String.length(input) <= 3 do
      Countries.get(String.upcase(input))
    end

    # Try by exact name
    country = country || case Countries.filter_by(:name, input) do
      [c | _] -> c
      _ -> nil
    end

    # Try by unofficial names
    country || case Countries.filter_by(:unofficial_names, input) do
      [c | _] -> c
      _ -> nil
    end
  end

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
          where: c.country_id == ^country.id and
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
    venue_attrs = %{
      name: data.name,
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

  defp create_venue(data, city, _source) do
    # All discovery sources use "scraper" as the venue source
    attrs = %{
      name: data.name,
      address: data.address,
      city: city.name,
      state: data.state,
      country: data.country_name,
      latitude: data.latitude,
      longitude: data.longitude,
      venue_type: "venue",
      place_id: data.place_id,
      source: "scraper",
      city_id: city.id
    }

    %Venue{}
    |> Venue.changeset(attrs)
    |> Repo.insert()
  end

  defp maybe_update_venue(venue, data) do
    updates = []

    updates = if is_nil(venue.place_id) && data.place_id do
      [{:place_id, data.place_id} | updates]
    else
      updates
    end

    updates = if is_nil(venue.latitude) && data.latitude do
      [{:latitude, data.latitude}, {:longitude, data.longitude} | updates]
    else
      updates
    end

    updates = if is_nil(venue.address) && data.address do
      [{:address, data.address} | updates]
    else
      updates
    end

    if Enum.any?(updates) do
      venue
      |> Venue.changeset(Map.new(updates))
      |> Repo.update()
    else
      {:ok, venue}
    end
  end
end