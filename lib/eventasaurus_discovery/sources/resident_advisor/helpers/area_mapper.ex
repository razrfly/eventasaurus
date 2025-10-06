defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Helpers.AreaMapper do
  @moduledoc """
  Maps city names and IDs to Resident Advisor area integer IDs.

  Area IDs are required for GraphQL queries. These must be discovered manually
  via browser DevTools by inspecting network requests on ra.co.

  ## Discovery Process

  1. Open https://ra.co/events/{country}/{city} in browser
  2. Open DevTools → Network → Filter "graphql"
  3. Scroll page to trigger event listing query
  4. Inspect request payload
  5. Find `variables.filters.areas.eq` value (integer)
  6. Add to mapping below

  ## TODO

  Area IDs need to be discovered for target cities. Placeholder values used below.
  Update these with actual area IDs from browser DevTools research.
  """

  require Logger

  # TODO: Replace placeholder IDs with actual area IDs from DevTools research
  # Format: {{city_name, country_name}, area_id}
  @area_mappings %{
    # United Kingdom
    {"London", "United Kingdom"} => 34,
    # Likely correct, needs verification

    # Germany
    {"Berlin", "Germany"} => nil,
    # TODO: Discover via DevTools

    # Poland
    {"Warsaw", "Poland"} => nil,
    # TODO: Discover via DevTools
    {"Kraków", "Poland"} => 455,

    # United States
    {"New York", "United States"} => nil,
    # TODO: Discover via DevTools
    {"Los Angeles", "United States"} => nil,
    # TODO: Discover via DevTools

    # France
    {"Paris", "France"} => nil,
    # TODO: Discover via DevTools

    # Netherlands
    {"Amsterdam", "Netherlands"} => nil,
    # TODO: Discover via DevTools

    # Spain
    {"Barcelona", "Spain"} => nil
    # TODO: Discover via DevTools

    # Add more cities as needed
  }

  @doc """
  Get Resident Advisor area ID for a city.

  ## Parameters
  - `city` - City struct with name and country

  ## Returns
  - `{:ok, area_id}` - Integer area ID
  - `{:error, :area_not_found}` - City not mapped yet

  ## Examples

      iex> AreaMapper.get_area_id(%{name: "London", country: %{name: "United Kingdom"}})
      {:ok, 34}

      iex> AreaMapper.get_area_id(%{name: "Unknown City", country: %{name: "Unknown"}})
      {:error, :area_not_found}
  """
  def get_area_id(%{name: city_name, country: %{name: country_name}}) do
    case find_area_id(city_name, country_name) do
      nil ->
        Logger.warning("""
        ⚠️  RA area ID not found for city
        City: #{city_name}, #{country_name}
        Action: Add area ID mapping via DevTools research
        """)

        {:error, :area_not_found}

      area_id ->
        {:ok, area_id}
    end
  end

  def get_area_id(_), do: {:error, :invalid_city_format}

  @doc """
  Check if a city has an area ID mapping.
  """
  def has_area_mapping?(city) do
    case get_area_id(city) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all mapped cities.
  """
  def list_mapped_cities do
    @area_mappings
    |> Enum.map(fn {{city, country}, area_id} ->
      %{city: city, country: country, area_id: area_id}
    end)
  end

  # Private functions

  defp find_area_id(city_name, country_name) do
    # Normalize city name for matching
    normalized_city = normalize_city_name(city_name)
    normalized_country = normalize_country_name(country_name)

    # Try exact match first
    case Map.get(@area_mappings, {city_name, country_name}) do
      nil ->
        # Try normalized match
        @area_mappings
        |> Enum.find(fn {{mapped_city, mapped_country}, _area_id} ->
          normalize_city_name(mapped_city) == normalized_city and
            normalize_country_name(mapped_country) == normalized_country
        end)
        |> case do
          {_key, area_id} -> area_id
          nil -> nil
        end

      area_id ->
        area_id
    end
  end

  defp normalize_city_name(name) do
    name
    |> String.downcase()
    |> String.trim()
    # Handle alternate spellings
    |> case do
      "krakow" -> "kraków"
      "warszawa" -> "warsaw"
      other -> other
    end
  end

  defp normalize_country_name(name) do
    name
    |> String.downcase()
    |> String.trim()
    # Handle alternate names
    |> case do
      "usa" -> "united states"
      "us" -> "united states"
      "uk" -> "united kingdom"
      "great britain" -> "united kingdom"
      other -> other
    end
  end
end
