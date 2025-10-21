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
    city = get_city_with_venues(city_id)

    venue_count = get_venue_count(city)

    if venue_count > 0 do
      {:error, :has_venues}
    else
      Repo.delete(city)
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
    City
    |> apply_filters(filters)
    |> join(:left, [c], v in assoc(c, :venues))
    |> group_by([c], c.id)
    |> select([c, v], %{
      city: c,
      venue_count: count(v.id)
    })
    |> preload([c], :country)
    |> order_by([c], c.name)
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

  defp validate_country_exists(changeset, %{country_id: country_id}) when not is_nil(country_id) do
    if Repo.get(Country, country_id) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :country_id, "does not exist")
    end
  end

  defp validate_country_exists(changeset, _attrs), do: changeset

  defp get_city_with_venues(city_id) do
    Repo.get!(City, city_id)
    |> Repo.preload(:venues)
  end

  defp get_venue_count(%City{} = city) do
    from(v in "venues", where: v.city_id == ^city.id, select: count(v.id))
    |> Repo.one()
  end
end
