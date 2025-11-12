defmodule EventasaurusDiscovery.Admin.CityManager do
  @moduledoc """
  Manages manual city creation and configuration for production.

  Provides CRUD operations for cities that are intentionally added
  before running scrapers, ensuring proper city center coordinates
  and discovery configuration.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.{City, Country}

  @doc """
  Creates a city with validation.

  ## Examples

      iex> create_city(%{
      ...>   name: "Sydney",
      ...>   country_id: 1,
      ...>   latitude: -33.8688,
      ...>   longitude: 151.2093
      ...> })
      {:ok, %City{}}

      iex> create_city(%{name: "Sydney"})
      {:error, %Ecto.Changeset{}}
  """
  def create_city(attrs) do
    %City{}
    |> City.changeset(attrs)
    |> validate_country_exists(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a city's details.

  ## Examples

      iex> update_city(city, %{latitude: -33.8688, longitude: 151.2093})
      {:ok, %City{}}
  """
  def update_city(%City{} = city, attrs) do
    city
    |> City.changeset(attrs)
    |> validate_country_exists(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a city if it has no venues.

  Returns {:error, :has_venues} if the city has associated venues.

  ## Examples

      iex> delete_city(city_id)
      {:ok, %City{}}

      iex> delete_city(city_with_venues_id)
      {:error, :has_venues}
  """
  def delete_city(city_id) do
    case Repo.get(City, city_id) do
      nil ->
        {:error, :not_found}

      city ->
        changeset = City.delete_changeset(city)

        case Repo.delete(changeset) do
          {:ok, _} = result ->
            result

          {:error, changeset} ->
            if Keyword.has_key?(changeset.errors, :id) do
              {:error, :has_venues}
            else
              {:error, changeset}
            end
        end
    end
  end

  @doc """
  Gets a single city by ID with preloaded associations.

  ## Examples

      iex> get_city(123)
      %City{country: %Country{}, ...}

      iex> get_city(999)
      nil
  """
  def get_city(id) do
    Repo.get(City, id)
    |> Repo.preload(:country)
  end

  @doc """
  Lists all cities with optional filters.

  ## Filters

  - `:search` - Search by city name (case-insensitive)
  - `:country_id` - Filter by country
  - `:discovery_enabled` - Filter by discovery status (true/false)

  ## Examples

      iex> list_cities()
      [%City{}, ...]

      iex> list_cities(%{search: "sydney"})
      [%City{name: "Sydney"}, ...]

      iex> list_cities(%{country_id: 1, discovery_enabled: true})
      [%City{}, ...]
  """
  def list_cities(filters \\ %{}) do
    City
    |> apply_filters(filters)
    |> preload(:country)
    |> order_by([c], c.name)
    |> Repo.all()
  end

  @doc """
  Lists all cities with venue counts.

  Returns list of cities with a virtual `:venue_count` field.
  """
  def list_cities_with_venue_counts(filters \\ %{}) do
    sort_by = filters[:sort_by] || "name"
    sort_dir = filters[:sort_dir] || "asc"

    City
    |> apply_filters(filters)
    |> join(:left, [c], v in assoc(c, :venues))
    |> group_by([c], c.id)
    |> select([c, v], %{
      city: c,
      venue_count: count(v.id)
    })
    |> preload([c], :country)
    |> apply_sorting(sort_by, sort_dir)
    |> Repo.all()
    |> Enum.map(fn %{city: city, venue_count: count} ->
      Map.put(city, :venue_count, count)
    end)
  end

  # Private functions

  defp apply_filters(query, filters) do
    query
    |> filter_by_search(filters[:search])
    |> filter_by_country(filters[:country_id])
    |> filter_by_discovery(filters[:discovery_enabled])
  end

  defp filter_by_search(query, nil), do: query
  defp filter_by_search(query, ""), do: query

  defp filter_by_search(query, search) do
    search_pattern = "%#{search}%"
    where(query, [c], ilike(c.name, ^search_pattern))
  end

  defp filter_by_country(query, nil), do: query

  defp filter_by_country(query, country_id) when is_binary(country_id) do
    case Integer.parse(country_id) do
      {id, _} -> where(query, [c], c.country_id == ^id)
      :error -> query
    end
  end

  defp filter_by_country(query, country_id) when is_integer(country_id) do
    where(query, [c], c.country_id == ^country_id)
  end

  defp filter_by_discovery(query, nil), do: query

  defp filter_by_discovery(query, discovery_enabled) when is_boolean(discovery_enabled) do
    where(query, [c], c.discovery_enabled == ^discovery_enabled)
  end

  defp filter_by_discovery(query, "true"), do: where(query, [c], c.discovery_enabled == true)
  defp filter_by_discovery(query, "false"), do: where(query, [c], c.discovery_enabled == false)
  defp filter_by_discovery(query, _), do: query

  defp apply_sorting(query, "name", "asc"), do: order_by(query, [c], asc: c.name)
  defp apply_sorting(query, "name", "desc"), do: order_by(query, [c], desc: c.name)
  defp apply_sorting(query, "venue_count", "asc"), do: order_by(query, [c, v], asc: count(v.id))
  defp apply_sorting(query, "venue_count", "desc"), do: order_by(query, [c, v], desc: count(v.id))
  defp apply_sorting(query, _, _), do: order_by(query, [c], asc: c.name)

  defp validate_country_exists(changeset, %{country_id: country_id})
       when not is_nil(country_id) do
    if Repo.get(Country, country_id) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :country_id, "does not exist")
    end
  end

  defp validate_country_exists(changeset, _attrs), do: changeset

  @doc """
  Counts cities with zero venues.
  """
  def count_orphaned_cities do
    from(c in City,
      left_join: v in assoc(c, :venues),
      group_by: c.id,
      having: count(v.id) == 0,
      select: c.id
    )
    |> Repo.all()
    |> length()
  end

  @doc """
  Deletes all cities with zero venues.

  Returns {:ok, count} where count is the number of cities deleted.
  Returns {:error, reason} if the transaction fails.
  """
  def delete_orphaned_cities do
    Repo.transaction(fn ->
      # Get IDs of cities with zero venues
      # Note: Transaction isolation + foreign key constraints prevent race conditions
      orphaned_city_ids =
        from(c in City,
          left_join: v in assoc(c, :venues),
          group_by: c.id,
          having: count(v.id) == 0,
          select: c.id
        )
        |> Repo.all()

      # Delete them all within the transaction
      {count, _} =
        from(c in City, where: c.id in ^orphaned_city_ids)
        |> Repo.delete_all()

      count
    end)
  end

  # ============================================================================
  # Alternate Names Management
  # ============================================================================

  @doc """
  Adds an alternate name to a city.

  ## Examples

      iex> add_alternate_name(city, "Warszawa")
      {:ok, %City{alternate_names: ["Warszawa", ...]}}

      iex> add_alternate_name(city, "")
      {:error, :empty_name}

      iex> add_alternate_name(city, "Warszawa")  # when already exists
      {:error, :already_exists}
  """
  def add_alternate_name(%City{} = city, alternate_name) when is_binary(alternate_name) do
    alternate_name = String.trim(alternate_name)

    cond do
      alternate_name == "" ->
        {:error, :empty_name}

      alternate_name in (city.alternate_names || []) ->
        {:error, :already_exists}

      true ->
        new_alternates = (city.alternate_names || []) ++ [alternate_name]

        city
        |> City.changeset(%{alternate_names: new_alternates})
        |> Repo.update()
    end
  end

  @doc """
  Removes an alternate name from a city.

  ## Examples

      iex> remove_alternate_name(city, "Warszawa")
      {:ok, %City{}}
  """
  def remove_alternate_name(%City{} = city, alternate_name) do
    new_alternates = List.delete(city.alternate_names || [], alternate_name)

    city
    |> City.changeset(%{alternate_names: new_alternates})
    |> Repo.update()
  end

  # ============================================================================
  # Duplicate Detection
  # ============================================================================

  @doc """
  Finds potential duplicate cities based on:
  - Similar names (case-insensitive)
  - Same country
  - Close proximity (within ~10km)

  Returns list of duplicate groups, where each group contains cities that
  might be duplicates of each other.

  ## Examples

      iex> find_potential_duplicates()
      [
        [%City{id: 6, name: "Warsaw"}, %City{id: 32, name: "Warszawa"}],
        [%City{id: 5, name: "Kraków"}, %City{id: 15, name: "Krakow"}]
      ]
  """
  def find_potential_duplicates do
    # Get all cities with their venue counts
    cities =
      from(c in City,
        left_join: v in assoc(c, :venues),
        group_by: c.id,
        select: %{
          city: c,
          venue_count: count(v.id)
        },
        order_by: [c.country_id, c.name]
      )
      |> preload([c], :country)
      |> Repo.all()
      |> Enum.map(fn %{city: city, venue_count: count} ->
        Map.put(city, :venue_count, count)
      end)

    # Group by country and find duplicates within each country
    cities
    |> Enum.group_by(& &1.country_id)
    |> Enum.flat_map(fn {_country_id, country_cities} ->
      find_duplicates_in_list(country_cities)
    end)
    |> Enum.reject(&(length(&1) < 2))
  end

  # Private helper to find duplicate cities within a list
  defp find_duplicates_in_list(cities) do
    # Compare each city with every other city
    cities
    |> Enum.with_index()
    |> Enum.flat_map(fn {city1, idx1} ->
      cities
      |> Enum.drop(idx1 + 1)
      |> Enum.filter(fn city2 ->
        cities_are_similar?(city1, city2)
      end)
      |> case do
        [] -> []
        matches -> [[city1 | matches]]
      end
    end)
    |> merge_overlapping_groups()
  end

  # Check if two cities are similar enough to be potential duplicates
  defp cities_are_similar?(city1, city2) do
    name_similar?(city1.name, city2.name) or
      location_similar?(city1, city2)
  end

  # Check if names are similar (case-insensitive, ignoring accents)
  defp name_similar?(name1, name2) do
    normalize_name(name1) == normalize_name(name2)
  end

  # Normalize name for comparison
  defp normalize_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[àáâãäå]/, "a")
    |> String.replace(~r/[èéêë]/, "e")
    |> String.replace(~r/[ìíîï]/, "i")
    |> String.replace(~r/[òóôõö]/, "o")
    |> String.replace(~r/[ùúûü]/, "u")
    |> String.replace(~r/[ýÿ]/, "y")
    |> String.replace(~r/[ñ]/, "n")
    |> String.replace(~r/[ç]/, "c")
    |> String.replace(~r/[ł]/, "l")
    |> String.replace(~r/[ß]/, "ss")
  end

  # Check if locations are similar (within ~10km)
  defp location_similar?(city1, city2) do
    case {city1.latitude, city1.longitude, city2.latitude, city2.longitude} do
      {lat1, lon1, lat2, lon2}
      when not is_nil(lat1) and not is_nil(lon1) and not is_nil(lat2) and not is_nil(lon2) ->
        lat1 = Decimal.to_float(lat1)
        lon1 = Decimal.to_float(lon1)
        lat2 = Decimal.to_float(lat2)
        lon2 = Decimal.to_float(lon2)

        distance_km = haversine_distance(lat1, lon1, lat2, lon2)
        distance_km < 10.0

      _ ->
        false
    end
  end

  # Calculate distance between two coordinates using Haversine formula
  defp haversine_distance(lat1, lon1, lat2, lon2) do
    earth_radius_km = 6371.0

    d_lat = :math.pi() * (lat2 - lat1) / 180.0
    d_lon = :math.pi() * (lon2 - lon1) / 180.0

    a =
      :math.sin(d_lat / 2) * :math.sin(d_lat / 2) +
        :math.cos(:math.pi() * lat1 / 180.0) * :math.cos(:math.pi() * lat2 / 180.0) *
          :math.sin(d_lon / 2) * :math.sin(d_lon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    earth_radius_km * c
  end

  # Merge overlapping duplicate groups
  defp merge_overlapping_groups(groups) do
    groups
    |> Enum.reduce([], fn group, acc ->
      # Find if this group overlaps with any existing group
      case Enum.find_index(acc, fn existing_group ->
             Enum.any?(group, fn city -> city in existing_group end)
           end) do
        nil ->
          # No overlap, add as new group
          [group | acc]

        idx ->
          # Overlap found, merge groups
          existing_group = Enum.at(acc, idx)
          merged_group = Enum.uniq(existing_group ++ group)
          List.replace_at(acc, idx, merged_group)
      end
    end)
    |> Enum.map(&Enum.sort_by(&1, fn city -> {-city.venue_count, city.id} end))
  end

  # ============================================================================
  # City Merging
  # ============================================================================

  @doc """
  Merges duplicate cities into a single canonical city.

  Moves all venues and events from source cities to the target city,
  optionally adds source city names as alternate names, then deletes
  the source cities.

  ## Parameters

  - `target_city_id` - The ID of the city to keep
  - `source_city_ids` - List of city IDs to merge into the target
  - `add_as_alternates` - Whether to add source city names as alternate names (default: true)

  ## Examples

      iex> merge_cities(6, [32], true)
      {:ok, %{
        target_city: %City{id: 6, name: "Warsaw", alternate_names: ["Warszawa"]},
        venues_moved: 132,
        events_moved: 245,
        cities_deleted: 1
      }}

      iex> merge_cities(6, [999], true)
      {:error, :source_city_not_found}
  """
  def merge_cities(target_city_id, source_city_ids, add_as_alternates \\ true)
      when is_list(source_city_ids) do
    Repo.transaction(fn ->
      # Load target city
      target_city = Repo.get!(City, target_city_id) |> Repo.preload(:country)

      # Load source cities
      source_cities =
        from(c in City,
          where: c.id in ^source_city_ids,
          preload: :country
        )
        |> Repo.all()

      if length(source_cities) != length(source_city_ids) do
        Repo.rollback(:source_city_not_found)
      end

      # Verify all cities are in the same country
      if Enum.any?(source_cities, &(&1.country_id != target_city.country_id)) do
        Repo.rollback(:cities_must_be_in_same_country)
      end

      # Move venues (events automatically follow through venue association)
      venues_moved =
        from(v in EventasaurusApp.Venues.Venue,
          where: v.city_id in ^source_city_ids
        )
        |> Repo.update_all(set: [city_id: target_city_id])
        |> elem(0)

      # Count affected events (for reporting only)
      events_count =
        from(e in "public_events",
          join: v in EventasaurusApp.Venues.Venue,
          on: e.venue_id == v.id,
          where: v.city_id == ^target_city_id
        )
        |> Repo.aggregate(:count)

      events_moved = events_count

      # Add source city names as alternate names if requested
      target_city =
        if add_as_alternates do
          new_alternates =
            source_cities
            |> Enum.map(& &1.name)
            |> Enum.reject(&(&1 in (target_city.alternate_names || [])))

          if new_alternates != [] do
            updated_alternates = (target_city.alternate_names || []) ++ new_alternates

            {:ok, updated_city} =
              target_city
              |> City.changeset(%{alternate_names: updated_alternates})
              |> Repo.update()

            updated_city
          else
            target_city
          end
        else
          target_city
        end

      # Delete source cities
      cities_deleted =
        from(c in City,
          where: c.id in ^source_city_ids
        )
        |> Repo.delete_all()
        |> elem(0)

      %{
        target_city: target_city,
        venues_moved: venues_moved,
        events_moved: events_moved,
        cities_deleted: cities_deleted
      }
    end)
  end
end
