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
  Finds an existing venue by place_id or name/city combination.
  """
  def find_existing_venue(%{place_id: place_id}) when not is_nil(place_id) do
    Repo.get_by(Venue, place_id: place_id)
  end

  def find_existing_venue(%{name: name, city_id: city_id}) do
    from(v in Venue,
      where: v.name == ^name and v.city_id == ^city_id,
      limit: 1
    )
    |> Repo.one()
  end

  def find_existing_venue(_), do: nil

  defp normalize_venue_data(data) do
    normalized = %{
      name: Normalizer.normalize_text(data[:name] || data["name"]),
      address: data[:address] || data["address"],
      city_name: data[:city] || data["city"],
      state: data[:state] || data["state"],
      country_name: data[:country] || data["country"],
      latitude: parse_coordinate(data[:latitude] || data["latitude"]),
      longitude: parse_coordinate(data[:longitude] || data["longitude"]),
      place_id: data[:place_id] || data["place_id"],
      metadata: data[:metadata] || data["metadata"] || %{}
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

    city = from(c in City,
      where: c.name == ^city_name and c.country_id == ^country.id,
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> create_city(city_name, country, data)
      existing -> existing
    end

    {:ok, city}
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
    %City{}
    |> City.changeset(%{
      name: name,
      slug: Normalizer.create_slug(name),
      country_id: country.id,
      latitude: data[:latitude],
      longitude: data[:longitude]
    })
    |> Repo.insert!()
  end

  defp find_or_create_venue(data, city, source) do
    venue_attrs = %{
      name: data.name,
      city_id: city.id,
      place_id: data.place_id
    }

    case find_existing_venue(venue_attrs) do
      nil ->
        create_venue(data, city, source)

      existing ->
        maybe_update_venue(existing, data)
    end
  end

  defp create_venue(data, city, source) do
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
      source: source,
      city_id: city.id,
      metadata: data.metadata
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