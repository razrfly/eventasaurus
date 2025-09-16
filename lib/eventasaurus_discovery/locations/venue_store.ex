defmodule EventasaurusDiscovery.Locations.VenueStore do
  @moduledoc """
  Handles finding or creating venues with deduplication logic.
  Uses PostGIS for geo-proximity matching and Ecto upserts for atomic operations.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country}
  import Ecto.Query
  require Logger

  @doc """
  Find or create venue using progressive matching strategy.
  Uses Ecto upserts for atomic operations.
  """
  def find_or_create_venue(attrs) do
    with {:ok, normalized_attrs} <- normalize_venue_attrs(attrs) do
      # Try each method in sequence, falling back to the next
      case find_by_proximity(normalized_attrs) do
        {:ok, venue} -> {:ok, venue}
        _ ->
          case find_by_name_and_city(normalized_attrs) do
            {:ok, venue} -> {:ok, venue}
            _ -> create_venue(normalized_attrs)
          end
      end
    else
      {:error, reason} = error ->
        Logger.error("Failed to find or create venue: #{inspect(reason)}")
        error
    end
  end

  # Step 1: Try geo-proximity match (50m radius)
  defp find_by_proximity(%{latitude: lat, longitude: lng, name: name, city_id: city_id})
       when not is_nil(lat) and not is_nil(lng) and not is_nil(city_id) do

    # Convert to float for PostGIS
    lat_float = to_float(lat)
    lng_float = to_float(lng)

    # Skip if coordinates couldn't be parsed
    if is_nil(lat_float) or is_nil(lng_float) do
      Logger.debug("Skipping proximity match due to invalid coordinates: #{inspect({lat, lng})}")
      nil
    else

    query = from v in Venue,
      where: v.city_id == ^city_id,
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      where: fragment(
        "ST_DWithin(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
        v.longitude,
        v.latitude,
        ^lng_float,
        ^lat_float,
        50  # meters
      ),
      order_by: fragment(
        "ST_Distance(ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography)",
        v.longitude,
        v.latitude,
        ^lng_float,
        ^lat_float
      ),
      limit: 1

      case Repo.one(query) do
        nil ->
          Logger.debug("No venue found by proximity at (#{lat}, #{lng})")
          nil
        venue ->
          # Check if names are similar enough
          if similar_names?(venue.name, name) do
            Logger.info("📍 Found venue by proximity: #{venue.name} (#{venue.id})")
            update_venue_if_needed(venue, %{latitude: lat, longitude: lng})
          else
            Logger.info("Found different venue at same location: #{venue.name} != #{name}")
            nil  # Different venue at same location
          end
      end
    end
  end
  defp find_by_proximity(_), do: nil

  # Step 2: Try exact name + city match using upsert
  defp find_by_name_and_city(%{name: name, city_id: city_id} = attrs) when not is_nil(city_id) do
    # The normalized_name will be set by the database trigger
    venue_attrs = Map.merge(attrs, %{
      normalized_name: normalize_for_comparison(name)
    })

    changeset = %Venue{}
    |> Venue.changeset(venue_attrs)

    # Try to find existing venue first by name and city
    existing = from(v in Venue,
      where: v.normalized_name == ^normalize_for_comparison(name) and v.city_id == ^city_id
    ) |> Repo.one()

    case existing do
      nil ->
        # Create new venue
        case Repo.insert(changeset) do
          {:ok, venue} ->
            Logger.info("🏢 Created new venue: #{venue.name} (#{venue.id})")
            {:ok, venue}
          {:error, changeset} ->
            Logger.error("Failed to create venue: #{inspect(changeset.errors)}")
            nil
        end
      venue ->
        # Update existing venue
        case Repo.update(Venue.changeset(venue, attrs)) do
          {:ok, venue} ->
            Logger.info("🏢 Updated existing venue: #{venue.name} (#{venue.id})")
            {:ok, venue}
          {:error, changeset} ->
            Logger.error("Failed to update venue: #{inspect(changeset.errors)}")
            {:ok, venue}  # Return the existing venue even if update failed
        end
    end
  rescue
    e ->
      Logger.error("Exception during upsert: #{inspect(e)}")
      nil
  end
  defp find_by_name_and_city(_), do: nil

  # Step 3: Create new venue (no matches found)
  defp create_venue(attrs) do
    changeset = %Venue{}
    |> Venue.changeset(attrs)

    case Repo.insert(changeset) do
      {:ok, venue} ->
        Logger.info("✨ Created new venue: #{venue.name} (#{venue.id})")
        {:ok, venue}
      {:error, changeset} ->
        # Try to handle unique constraint violations
        if has_unique_violation?(changeset) do
          Logger.info("Venue already exists, attempting to find it")
          find_existing_venue(attrs)
        else
          Logger.error("Failed to create venue: #{inspect(changeset.errors)}")
          {:error, changeset}
        end
    end
  end

  # Fallback: Find existing venue when creation fails
  defp find_existing_venue(%{name: name, city_id: city_id}) when not is_nil(city_id) do
    normalized_name = normalize_for_comparison(name)

    query = from v in Venue,
      where: v.normalized_name == ^normalized_name and v.city_id == ^city_id,
      limit: 1

    case Repo.one(query) do
      nil -> {:error, :venue_not_found}
      venue -> {:ok, venue}
    end
  end
  defp find_existing_venue(_), do: {:error, :invalid_venue_data}

  # Check if two venue names are similar enough
  defp similar_names?(name1, name2) do
    n1 = normalize_for_comparison(name1)
    n2 = normalize_for_comparison(name2)

    # Exact match after normalization
    n1 == n2 ||
    # Fuzzy match with high threshold (using Akin library)
    Akin.compare(n1, n2) > 0.85 ||
    # One name contains the other (for "Arena" vs "Tauron Arena Kraków")
    String.contains?(n1, n2) || String.contains?(n2, n1)
  end

  defp normalize_for_comparison(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.normalize(:nfc)
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
  defp normalize_for_comparison(_), do: ""

  defp normalize_venue_attrs(attrs) do
    normalized = attrs
    |> Map.put_new(:venue_type, "venue")
    |> Map.put_new(:source, "scraper")
    |> ensure_numeric_coordinates()
    |> ensure_city_id()

    {:ok, normalized}
  end

  defp ensure_numeric_coordinates(%{latitude: lat, longitude: lng} = attrs)
       when is_binary(lat) or is_binary(lng) do
    # Convert to floats for the database
    attrs
    |> Map.put(:latitude, to_float(lat))
    |> Map.put(:longitude, to_float(lng))
  end
  defp ensure_numeric_coordinates(attrs), do: attrs

  defp ensure_city_id(%{city_id: city_id} = attrs) when not is_nil(city_id), do: attrs
  defp ensure_city_id(%{city_name: city_name, country_code: country_code} = attrs)
       when not is_nil(city_name) and not is_nil(country_code) do
    # Try to find or create the city
    case find_or_create_city(city_name, country_code) do
      {:ok, city} -> Map.put(attrs, :city_id, city.id)
      _ -> attrs
    end
  end
  defp ensure_city_id(attrs), do: attrs

  defp find_or_create_city(city_name, country_code) do
    # First find or create country
    with {:ok, country} <- find_or_create_country(country_code),
         {:ok, city} <- find_or_create_city_in_country(city_name, country) do
      {:ok, city}
    end
  end

  defp find_or_create_country(country_code) when is_binary(country_code) do
    code = String.upcase(country_code)

    case Repo.get_by(Country, code: code) do
      nil ->
        # Create with a default name based on code
        %Country{}
        |> Country.changeset(%{
          name: country_name_from_code(code),
          code: code
        })
        |> Repo.insert()
        |> case do
          {:ok, country} ->
            {:ok, country}
          {:error, %Ecto.Changeset{} = changeset} ->
            # Handle race condition - another process may have created the country
            case Repo.get_by(Country, code: code) do
              nil -> {:error, changeset}
              country -> {:ok, country}
            end
        end
      country ->
        {:ok, country}
    end
  end

  defp find_or_create_city_in_country(city_name, %Country{id: country_id}) do
    # Generate the slug that will be used
    slug = Slug.slugify(city_name)

    # Try to find by slug and country_id (the actual unique constraint)
    case Repo.get_by(City, slug: slug, country_id: country_id) do
      nil ->
        %City{}
        |> City.changeset(%{
          name: city_name,
          country_id: country_id
        })
        |> Repo.insert()
        |> case do
          {:ok, city} ->
            {:ok, city}
          {:error, %Ecto.Changeset{} = changeset} ->
            # Handle race condition - another process may have created the city
            # Try to fetch by slug which is what the unique constraint is on
            case Repo.get_by(City, slug: slug, country_id: country_id) do
              nil ->
                # Also try by name as fallback
                case Repo.get_by(City, name: city_name, country_id: country_id) do
                  nil -> {:error, changeset}
                  city -> {:ok, city}
                end
              city ->
                {:ok, city}
            end
        end
      city ->
        {:ok, city}
    end
  end

  # Helper to get country name from code using the countries library
  defp country_name_from_code(code) when is_binary(code) do
    upcase_code = String.upcase(code)
    case Countries.get(upcase_code) do
      nil ->
        Logger.warning("Unknown country code: #{code}, using code as name")
        upcase_code
      country ->
        country.name
    end
  end
  defp country_name_from_code(_), do: "Unknown"


  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1.0
  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end
  defp to_float(nil), do: nil
  defp to_float(_), do: nil

  defp update_venue_if_needed(venue, updates) do
    if should_update_venue?(venue, updates) do
      venue
      |> Venue.changeset(updates)
      |> Repo.update()
    else
      {:ok, venue}
    end
  end

  defp should_update_venue?(venue, %{latitude: lat, longitude: lng}) do
    is_nil(venue.latitude) || is_nil(venue.longitude) ||
    !coords_equal?(venue.latitude, lat) || !coords_equal?(venue.longitude, lng)
  end
  defp should_update_venue?(_, _), do: false

  defp coords_equal?(nil, _), do: false
  defp coords_equal?(_, nil), do: false
  defp coords_equal?(coord1, coord2) do
    # Compare coordinates with small tolerance
    f1 = to_float(coord1)
    f2 = to_float(coord2)
    if is_nil(f1) or is_nil(f2) do
      false
    else
      abs(f1 - f2) < 0.00001
    end
  end

  defp has_unique_violation?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_msg, opts}} ->
      opts[:constraint] == :unique
    end)
  end
end