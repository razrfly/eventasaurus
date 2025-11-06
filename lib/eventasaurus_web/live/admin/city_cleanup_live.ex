defmodule EventasaurusWeb.Admin.CityCleanupLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Helpers.CityResolver
  alias Ecto.Multi

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
       search_results: [],
       bulk_suggestions: %{}
     )}
  end

  @impl true
  def handle_event("suggest", %{"venue_id" => venue_id}, socket) do
    venue = Repo.get!(Venue, venue_id)
    suggestion = generate_suggestion_for_venue(venue)

    {:noreply, assign(socket, suggestion: suggestion, current_venue: venue)}
  end

  @impl true
  def handle_event("suggest_all", %{"city_id" => city_id}, socket) do
    city = Repo.get!(City, String.to_integer(city_id)) |> Repo.preload(:venues)

    # Generate suggestions for all venues
    suggestions =
      city.venues
      |> Enum.map(fn venue ->
        suggestion = generate_suggestion_for_venue(venue)
        {venue.id, suggestion}
      end)
      |> Enum.into(%{})

    {:noreply, assign(socket, bulk_suggestions: Map.put(socket.assigns.bulk_suggestions, city.id, suggestions))}
  end

  @impl true
  def handle_event("clear_bulk_suggestions", %{"city_id" => city_id}, socket) do
    bulk_suggestions = Map.delete(socket.assigns.bulk_suggestions, String.to_integer(city_id))
    {:noreply, assign(socket, bulk_suggestions: bulk_suggestions)}
  end

  @impl true
  def handle_event("reassign", %{"venue_id" => venue_id, "city_id" => city_id}, socket) do
    venue = Repo.get!(Venue, venue_id)
    venue_city_id = venue.city_id  # Get the current city_id BEFORE reassigning
    venue_id_int = String.to_integer(venue_id)

    case reassign_venue(venue, String.to_integer(city_id)) do
      {:ok, _venue} ->
        cities = load_problematic_cities()

        # Remove only THIS venue from bulk suggestions, not the entire city
        updated_bulk_suggestions =
          if venue_city_id do
            city_suggestions = Map.get(socket.assigns.bulk_suggestions, venue_city_id, %{})
            updated_city_suggestions = Map.delete(city_suggestions, venue_id_int)

            if map_size(updated_city_suggestions) == 0 do
              # If no more venues have suggestions, remove the city entry
              Map.delete(socket.assigns.bulk_suggestions, venue_city_id)
            else
              # Keep the city but update its suggestions
              Map.put(socket.assigns.bulk_suggestions, venue_city_id, updated_city_suggestions)
            end
          else
            socket.assigns.bulk_suggestions
          end

        {:noreply,
         assign(socket,
           cities: cities,
           suggestion: nil,
           current_venue: nil,
           bulk_suggestions: updated_bulk_suggestions
         )
         |> put_flash(:info, "Venue reassigned successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to reassign venue")}
    end
  end

  @impl true
  def handle_event("create_and_assign", %{"venue_id" => venue_id, "city_id" => city_id}, socket) do
    venue = Repo.get!(Venue, venue_id)
    venue_city_id = venue.city_id  # Get the current city_id BEFORE reassigning
    venue_id_int = String.to_integer(venue_id)
    city_id_int = String.to_integer(city_id)

    # Get the correct suggestion (from bulk or individual)
    suggestion = get_active_suggestion(socket, city_id_int, venue_id_int)

    # Create the new city
    city_attrs = %{
      name: suggestion.city_name,
      latitude: suggestion.venue_latitude,
      longitude: suggestion.venue_longitude,
      country_id: suggestion.country_id
    }

    case create_city_and_assign(city_attrs, venue) do
      {:ok, {city, _venue}} ->
        cities = load_problematic_cities()

        # Remove only THIS venue from bulk suggestions, not the entire city
        updated_bulk_suggestions =
          if venue_city_id do
            city_suggestions = Map.get(socket.assigns.bulk_suggestions, venue_city_id, %{})
            updated_city_suggestions = Map.delete(city_suggestions, venue_id_int)

            if map_size(updated_city_suggestions) == 0 do
              # If no more venues have suggestions, remove the city entry
              Map.delete(socket.assigns.bulk_suggestions, venue_city_id)
            else
              # Keep the city but update its suggestions
              Map.put(socket.assigns.bulk_suggestions, venue_city_id, updated_city_suggestions)
            end
          else
            socket.assigns.bulk_suggestions
          end

        {:noreply,
         assign(socket,
           cities: cities,
           suggestion: nil,
           current_venue: nil,
           bulk_suggestions: updated_bulk_suggestions
         )
         |> put_flash(:info, "City '#{city.name}' created and venue assigned successfully")}

      {:error, :missing_country} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot create city: country is unknown. Please assign venue to an existing city first."
         )}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)

        {:noreply,
         put_flash(
           socket,
           :error,
           "Failed to create city: #{errors}"
         )}
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

  defp get_active_suggestion(socket, city_id, venue_id) do
    # Check bulk suggestions first
    bulk_suggestion =
      socket.assigns.bulk_suggestions
      |> Map.get(city_id, %{})
      |> Map.get(venue_id)

    # Fall back to individual suggestion if venue matches
    individual_suggestion =
      if socket.assigns.current_venue && socket.assigns.current_venue.id == venue_id do
        socket.assigns.suggestion
      else
        nil
      end

    bulk_suggestion || individual_suggestion
  end

  defp generate_suggestion_for_venue(venue) do
    case CityResolver.resolve_city(venue.latitude, venue.longitude) do
      {:ok, city_name} ->
        # Find existing city with this name (may be multiple with same name)
        # If multiple exist, find the closest one to the venue
        city = find_nearest_city(city_name, venue.latitude, venue.longitude)

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
          # Store venue coordinates and country for creation
          venue_with_city = Repo.preload(venue, :city_ref)
          country_id = if venue_with_city.city_ref, do: venue_with_city.city_ref.country_id, else: nil

          %{
            city: nil,
            city_name: city_name,
            confidence: 0.5,
            distance: nil,
            needs_creation: true,
            already_assigned: false,
            venue_latitude: venue.latitude,
            venue_longitude: venue.longitude,
            country_id: country_id
          }
        end

      {:error, reason} ->
        Logger.warning("Failed to resolve city for venue #{venue.id}: #{inspect(reason)}")
        nil
    end
  end

  defp find_nearest_city(city_name, venue_lat, venue_lng) do
    import Ecto.Query

    # Get all cities with this name
    cities =
      from(c in City,
        where: c.name == ^city_name,
        preload: [:country]
      )
      |> Repo.all()

    case cities do
      [] ->
        nil

      [single_city] ->
        # Only one city with this name, return it
        single_city

      multiple_cities ->
        # Multiple cities with same name - find the closest one
        multiple_cities
        |> Enum.map(fn city ->
          distance = calculate_distance_coords(venue_lat, venue_lng, city.latitude, city.longitude)
          {city, distance}
        end)
        |> Enum.filter(fn {_city, distance} -> !is_nil(distance) end)
        |> Enum.min_by(fn {_city, distance} -> distance end, fn -> {nil, nil} end)
        |> elem(0)
    end
  end

  defp calculate_distance_coords(lat1, lng1, lat2, lng2) do
    # Simple Haversine formula for distance in km
    # Returns nil if any coordinates are missing
    with lat1 when not is_nil(lat1) <- lat1,
         lng1 when not is_nil(lng1) <- lng1,
         lat2 when not is_nil(lat2) <- lat2,
         lng2 when not is_nil(lng2) <- lng2 do
      # Convert city Decimal coordinates to floats if needed
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
    # Sort by venue count descending to preserve ordering from first query
    from(c in City,
      where: c.id in ^city_ids,
      preload: [:venues, :country]
    )
    |> Repo.all()
    |> Enum.sort_by(&length(&1.venues), :desc)
  end

  defp reassign_venue(venue, new_city_id) do
    venue
    |> Ecto.Changeset.change(city_id: new_city_id)
    |> Repo.update()
  end

  defp create_city_and_assign(city_attrs, venue) do
    # Check if country_id is present
    if is_nil(city_attrs.country_id) do
      {:error, :missing_country}
    else
      # Use a transaction to ensure both operations succeed or fail together
      Multi.new()
      |> Multi.insert(:city, City.changeset(%City{}, city_attrs))
      |> Multi.update(:venue, fn %{city: city} ->
        Ecto.Changeset.change(venue, city_id: city.id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{city: city, venue: venue}} -> {:ok, {city, venue}}
        {:error, _operation, changeset, _changes} -> {:error, changeset}
      end
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
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
    calculate_distance_coords(venue.latitude, venue.longitude, city.latitude, city.longitude)
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

  defp pattern_badge_classes(city_name) do
    case pattern_color(city_name) do
      "orange" -> "bg-orange-100 text-orange-800"
      "red" -> "bg-red-100 text-red-800"
      "gray" -> "bg-gray-100 text-gray-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp confidence_badge_classes(confidence) do
    case confidence_color(confidence) do
      "green" -> "bg-green-100 text-green-800"
      "yellow" -> "bg-yellow-100 text-yellow-800"
      "red" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
