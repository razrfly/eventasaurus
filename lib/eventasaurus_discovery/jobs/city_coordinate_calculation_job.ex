defmodule EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob do
  @moduledoc """
  Calculates city center coordinates based on the average location of all venues
  within that city. Runs on-demand after scraping, but max once per 24 hours.

  This ensures city coordinates reflect the actual center of activity rather than
  geographic/political boundaries.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    priority: 2

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City

  require Logger

  @hours_between_updates 24

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_id = args["city_id"]
    force = args["force"] || false

    with {:ok, city} <- get_city(city_id),
         {:ok, :should_update} <- check_update_needed(city, force),
         {:ok, coordinates} <- calculate_coordinates(city),
         {:ok, updated_city} <- update_city_coordinates(city, coordinates) do
      Logger.info("""
      ✅ Updated coordinates for #{updated_city.name}
      Lat: #{Decimal.to_float(updated_city.latitude)}, Lng: #{Decimal.to_float(updated_city.longitude)}
      Based on #{coordinates.venue_count} venues
      """)

      {:ok,
       %{
         city: updated_city.name,
         latitude: Decimal.to_float(updated_city.latitude),
         longitude: Decimal.to_float(updated_city.longitude),
         venue_count: coordinates.venue_count
       }}
    else
      {:ok, :skip} ->
        Logger.debug("Skipping coordinate update for city #{city_id} - recently updated")
        {:ok, :skipped}

      {:error, :no_venues} ->
        Logger.debug("No venues with coordinates found for city #{city_id}")
        {:ok, :no_venues}

      {:error, :city_not_found} ->
        # City doesn't exist (possibly deleted or invalid ID) - don't retry
        Logger.warning("City #{city_id} not found - skipping coordinate calculation")
        {:ok, :city_not_found}

      error ->
        Logger.error("Failed to update city coordinates: #{inspect(error)}")
        error
    end
  end

  defp get_city(city_id) do
    case Repo.get(City, city_id) do
      nil -> {:error, :city_not_found}
      city -> {:ok, city}
    end
  end

  defp check_update_needed(%City{updated_at: updated_at, latitude: lat, longitude: lng}, force) do
    cond do
      # Force flag overrides all checks
      force ->
        {:ok, :should_update}

      # If coordinates don't exist yet, always update
      is_nil(lat) or is_nil(lng) ->
        {:ok, :should_update}

      # Check if city was updated in the last 24 hours
      true ->
        hours_since_update =
          NaiveDateTime.diff(NaiveDateTime.utc_now(), updated_at, :hour)

        if hours_since_update >= @hours_between_updates do
          {:ok, :should_update}
        else
          {:ok, :skip}
        end
    end
  end

  defp calculate_coordinates(%City{id: city_id, discovery_enabled: discovery_enabled} = city) do
    if discovery_enabled and not is_nil(city.latitude) and not is_nil(city.longitude) do
      # For active cities with coordinates, use geographic radius matching
      calculate_coordinates_geographic(city)
    else
      # For inactive cities or cities without initial coordinates, use city_id matching
      calculate_coordinates_by_city_id(city_id)
    end
  end

  defp calculate_coordinates_by_city_id(city_id) do
    # Calculate average coordinates from all venues linked to this city_id
    # that have valid coordinates
    query =
      from(v in Venue,
        where: v.city_id == ^city_id,
        where: not is_nil(v.latitude) and not is_nil(v.longitude),
        select: %{
          avg_lat: type(avg(v.latitude), :decimal),
          avg_lng: type(avg(v.longitude), :decimal),
          count: count(v.id)
        }
      )

    case Repo.one(query) do
      %{avg_lat: lat, avg_lng: lng, count: count} when not is_nil(lat) and count > 0 ->
        {:ok, %{latitude: lat, longitude: lng, venue_count: count}}

      _ ->
        {:error, :no_venues}
    end
  end

  defp calculate_coordinates_geographic(%City{
         latitude: city_lat,
         longitude: city_lng
       }) do
    # For active cities, find all venues within geographic radius
    # Default radius: 20km (suitable for major cities)
    # TODO: Add radius_km field to cities table for per-city configuration
    radius = 20.0

    # Calculate bounding box (approximate, faster than ST_DWithin)
    # 1 degree latitude ≈ 111km, 1 degree longitude ≈ 111km * cos(latitude)
    # Convert to float for Ecto query compatibility
    lat_float = Decimal.to_float(city_lat)
    lng_float = Decimal.to_float(city_lng)

    lat_delta = radius / 111.0
    lng_delta = radius / (111.0 * :math.cos(lat_float * :math.pi() / 180.0))

    min_lat = lat_float - lat_delta
    max_lat = lat_float + lat_delta
    min_lng = lng_float - lng_delta
    max_lng = lng_float + lng_delta

    query =
      from(v in Venue,
        where: not is_nil(v.latitude) and not is_nil(v.longitude),
        where: v.latitude >= ^min_lat and v.latitude <= ^max_lat,
        where: v.longitude >= ^min_lng and v.longitude <= ^max_lng,
        select: %{
          avg_lat: type(avg(v.latitude), :decimal),
          avg_lng: type(avg(v.longitude), :decimal),
          count: count(v.id)
        }
      )

    case Repo.one(query) do
      %{avg_lat: lat, avg_lng: lng, count: count} when not is_nil(lat) and count > 0 ->
        {:ok, %{latitude: lat, longitude: lng, venue_count: count}}

      _ ->
        {:error, :no_venues}
    end
  end

  defp update_city_coordinates(%City{id: city_id}, %{latitude: lat, longitude: lng}) do
    # Update the city coordinates using Repo.update_all for efficiency
    {updated_count, updated_cities} =
      from(c in City, where: c.id == ^city_id, select: c)
      |> Repo.update_all(
        [
          set: [
            latitude: lat,
            longitude: lng,
            updated_at: NaiveDateTime.utc_now()
          ]
        ],
        returning: true
      )

    if updated_count > 0 do
      {:ok, List.first(updated_cities)}
    else
      {:error, :update_failed}
    end
  end

  @doc """
  Convenience function to schedule a coordinate update for a city.
  Used by other modules to trigger updates.

  Options:
  - `force`: When true, bypasses the 24h uniqueness window
  """
  def schedule_update(city_id, force \\ false) when is_integer(city_id) do
    args = if force, do: %{city_id: city_id, force: true}, else: %{city_id: city_id}

    unique =
      if force do
        # Allow bypassing the 24h window but dedupe identical forced submissions briefly (60 seconds)
        [
          fields: [:args, :queue, :worker],
          keys: [:city_id, :force],
          period: 60,
          states: [:available, :scheduled, :executing]
        ]
      else
        # At most one job per city per 24h across relevant states
        [
          fields: [:args, :queue, :worker],
          keys: [:city_id],
          period: 86_400,
          states: [:available, :scheduled, :executing]
        ]
      end

    args
    |> __MODULE__.new(unique: unique)
    |> Oban.insert()
  end
end
