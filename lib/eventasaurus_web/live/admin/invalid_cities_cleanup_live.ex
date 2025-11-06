defmodule EventasaurusWeb.Admin.InvalidCitiesCleanupLive do
  use EventasaurusWeb, :live_view
  import Ecto.Query
  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusApp.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Load invalid cities with suggestions
      invalid_cities = load_invalid_cities_with_suggestions()

      {:ok,
       socket
       |> assign(:invalid_cities, invalid_cities)
       |> assign(:loading, false)
       |> assign(:processing, nil)}
    else
      {:ok,
       socket
       |> assign(:invalid_cities, [])
       |> assign(:loading, true)
       |> assign(:processing, nil)}
    end
  end

  @impl true
  def handle_event("merge_city", %{"invalid_id" => invalid_id, "replacement_id" => replacement_id}, socket) do
    invalid_id = String.to_integer(invalid_id)
    replacement_id = String.to_integer(replacement_id)

    # Show processing state
    socket = assign(socket, :processing, invalid_id)

    case CityManager.merge_cities(replacement_id, invalid_id) do
      {:ok, _result} ->
        # Reload the list after successful merge
        invalid_cities = load_invalid_cities_with_suggestions()

        {:noreply,
         socket
         |> assign(:invalid_cities, invalid_cities)
         |> assign(:processing, nil)
         |> put_flash(:info, "Successfully merged cities")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:processing, nil)
         |> put_flash(:error, "Failed to merge cities: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("skip_city", %{"invalid_id" => invalid_id}, socket) do
    invalid_id = String.to_integer(invalid_id)

    # Remove from current list (temporary skip)
    invalid_cities = Enum.reject(socket.assigns.invalid_cities, fn {city, _, _} -> city.id == invalid_id end)

    {:noreply,
     socket
     |> assign(:invalid_cities, invalid_cities)
     |> put_flash(:info, "Skipped city (will appear on next reload)")}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    invalid_cities = load_invalid_cities_with_suggestions()

    {:noreply,
     socket
     |> assign(:invalid_cities, invalid_cities)
     |> put_flash(:info, "Refreshed invalid cities list")}
  end

  # Private Functions

  defp load_invalid_cities_with_suggestions do
    invalid_cities = CityManager.find_invalid_cities()

    # For each invalid city, get suggestion and venue count
    Enum.map(invalid_cities, fn city ->
      suggestion_result = CityManager.suggest_replacement_city(city)
      venue_count = count_venues_for_city(city.id)

      {city, suggestion_result, venue_count}
    end)
  end

  defp count_venues_for_city(city_id) do
    Repo.one(
      from v in EventasaurusApp.Venues.Venue,
        where: v.city_id == ^city_id,
        select: count(v.id)
    )
  end
end
