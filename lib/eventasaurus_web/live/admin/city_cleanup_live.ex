defmodule EventasaurusWeb.Admin.CityCleanupLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Helpers.CityResolver

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    cities = load_problematic_cities()

    {:ok,
     assign(socket,
       cities: cities,
       suggestion: nil,
       current_venue: nil,
       search_query: "",
       search_results: []
     )}
  end

  @impl true
  def handle_event("suggest", %{"venue_id" => venue_id}, socket) do
    venue = Repo.get!(Venue, venue_id) |> Repo.preload(:city_ref)

    suggestion =
      case CityResolver.resolve_city(venue.latitude, venue.longitude) do
        {:ok, city_name} ->
          # Find existing city with this name
          city = Repo.get_by(City, name: city_name) |> Repo.preload(:country)

          if city do
            # Check if this is the same city the venue is already assigned to
            if city.id == venue.city_id do
              %{
                city: city,
                city_name: city_name,
                confidence: 1.0,
                distance: 0,
                needs_creation: false,
                already_assigned: true
              }
            else
              distance = calculate_distance(venue, city)
              confidence = calculate_confidence(distance)

              %{
                city: city,
                city_name: city_name,
                confidence: confidence,
                distance: distance,
                needs_creation: false,
                already_assigned: false
              }
            end
          else
            # City doesn't exist in database yet
            %{
              city: nil,
              city_name: city_name,
              confidence: 0.5,
              distance: nil,
              needs_creation: true,
              already_assigned: false
            }
          end

        {:error, reason} ->
          Logger.warning("Failed to resolve city for venue #{venue.id}: #{inspect(reason)}")
          nil
      end

    {:noreply, assign(socket, suggestion: suggestion, current_venue: venue)}
  end

  @impl true
  def handle_event("reassign", %{"venue_id" => venue_id, "city_id" => city_id}, socket) do
    venue = Repo.get!(Venue, venue_id)

    case reassign_venue(venue, String.to_integer(city_id)) do
      {:ok, _venue} ->
        cities = load_problematic_cities()

        {:noreply,
         assign(socket,
           cities: cities,
           suggestion: nil,
           current_venue: nil
         )
         |> put_flash(:info, "Venue reassigned successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to reassign venue")}
    end
  end

  @impl true
  def handle_event("delete_city", %{"id" => city_id}, socket) do
    city = Repo.get!(City, String.to_integer(city_id)) |> Repo.preload(:venues)

    if Enum.empty?(city.venues) do
      case Repo.delete(city) do
        {:ok, _city} ->
          cities = load_problematic_cities()

          {:noreply,
           assign(socket, cities: cities)
           |> put_flash(:info, "City '#{city.name}' deleted successfully")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to delete city")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Cannot delete city with venues (#{length(city.venues)} remaining)")}
    end
  end

  @impl true
  def handle_event("search_cities", %{"query" => query}, socket) do
    results = search_cities(query)
    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  @impl true
  def handle_event("clear_suggestion", _params, socket) do
    {:noreply, assign(socket, suggestion: nil, current_venue: nil, search_results: [])}
  end

  # Private functions

  defp load_problematic_cities do
    import Ecto.Query

    # First get city IDs with venue counts
    city_ids_query =
      from c in City,
        left_join: v in assoc(c, :venues),
        where:
          fragment("? ~ '^[0-9]'", c.name) or
            ilike(c.name, "%street%") or
            ilike(c.name, "%road%") or
            ilike(c.name, "the %"),
        group_by: c.id,
        having: count(v.id) > 0,
        order_by: [desc: count(v.id)],
        select: c.id

    city_ids = Repo.all(city_ids_query)

    # Then load the cities with their venues and countries
    from(c in City,
      where: c.id in ^city_ids,
      preload: [:venues, :country]
    )
    |> Repo.all()
  end

  defp reassign_venue(venue, new_city_id) do
    venue
    |> Ecto.Changeset.change(city_id: new_city_id)
    |> Repo.update()
  end

  defp search_cities(query) when byte_size(query) < 2, do: []

  defp search_cities(query) do
    import Ecto.Query

    pattern = "%#{query}%"

    from(c in City,
      left_join: co in assoc(c, :country),
      where: ilike(c.name, ^pattern),
      order_by: c.name,
      limit: 10,
      preload: [country: co]
    )
    |> Repo.all()
  end

  defp calculate_distance(venue, city) do
    # Simple Haversine formula for distance in km
    # Returns nil if either coordinates are missing
    # Note: venue coords are floats, city coords are Decimals - convert to float
    with lat1 when not is_nil(lat1) <- venue.latitude,
         lng1 when not is_nil(lng1) <- venue.longitude,
         lat2 when not is_nil(lat2) <- city.latitude,
         lng2 when not is_nil(lng2) <- city.longitude do
      # Convert city Decimal coordinates to floats
      lat2_float = if is_struct(lat2, Decimal), do: Decimal.to_float(lat2), else: lat2
      lng2_float = if is_struct(lng2, Decimal), do: Decimal.to_float(lng2), else: lng2

      lat1_rad = lat1 * :math.pi() / 180
      lat2_rad = lat2_float * :math.pi() / 180
      delta_lat = (lat2_float - lat1) * :math.pi() / 180
      delta_lng = (lng2_float - lng1) * :math.pi() / 180

      a =
        :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
          :math.cos(lat1_rad) * :math.cos(lat2_rad) *
            :math.sin(delta_lng / 2) * :math.sin(delta_lng / 2)

      c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
      6371 * c
    else
      _ -> nil
    end
  end

  defp calculate_confidence(nil), do: 0.3
  defp calculate_confidence(distance) when distance < 10, do: 0.95
  defp calculate_confidence(distance) when distance < 25, do: 0.75
  defp calculate_confidence(distance) when distance < 50, do: 0.50
  defp calculate_confidence(_distance), do: 0.25

  defp confidence_label(confidence) when confidence >= 0.8, do: "High"
  defp confidence_label(confidence) when confidence >= 0.5, do: "Medium"
  defp confidence_label(_confidence), do: "Low"

  defp confidence_color(confidence) when confidence >= 0.8, do: "green"
  defp confidence_color(confidence) when confidence >= 0.5, do: "yellow"
  defp confidence_color(_confidence), do: "red"

  defp pattern_badge(city_name) do
    cond do
      Regex.match?(~r/^[0-9]/, city_name) -> "Street Address"
      Regex.match?(~r/^the /i, city_name) -> "Venue Name"
      Regex.match?(~r/(street|road|avenue|lane)/i, city_name) -> "Street Name"
      true -> "Other"
    end
  end

  defp pattern_color(city_name) do
    cond do
      Regex.match?(~r/^[0-9]/, city_name) -> "orange"
      Regex.match?(~r/^the /i, city_name) -> "red"
      Regex.match?(~r/(street|road|avenue|lane)/i, city_name) -> "orange"
      true -> "gray"
    end
  end
end
