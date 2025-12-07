defmodule EventasaurusWeb.Admin.CityDuplicatesLive do
  @moduledoc """
  Admin page for managing city alternate names and detecting/merging duplicates.

  Features:
  - Detect potential duplicate cities
  - Merge duplicate cities
  - Add/remove alternate names
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusApp.Repo

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "City Duplicates & Alternate Names")
      |> assign(:duplicate_groups, [])
      |> assign(:selected_city, nil)
      |> assign(:new_alternate_name, "")
      |> assign(:loading, true)
      |> assign(:active_tab, "duplicates")
      |> assign(:detection_time_ms, nil)

    # Load duplicates asynchronously to avoid blocking mount
    send(self(), :load_duplicates)

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_duplicates, socket) do
    {time_us, duplicate_groups} = :timer.tc(fn -> CityManager.find_potential_duplicates() end)
    time_ms = div(time_us, 1000)

    socket =
      socket
      |> assign(:duplicate_groups, duplicate_groups)
      |> assign(:loading, false)
      |> assign(:detection_time_ms, time_ms)

    {:noreply, socket}
  end

  @impl true
  def handle_event("detect_duplicates", _params, socket) do
    # Start async detection
    send(self(), :load_duplicates)

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:detection_time_ms, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("merge_cities", params, socket) do
    target_id = String.to_integer(params["target_id"])
    all_city_ids = String.split(params["source_ids"], ",") |> Enum.map(&String.to_integer/1)
    # Filter out the target city from the source list
    source_ids = Enum.reject(all_city_ids, &(&1 == target_id))
    add_as_alternates = params["add_as_alternates"] == "true"

    case CityManager.merge_cities(target_id, source_ids, add_as_alternates) do
      {:ok, result} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Successfully merged cities! Moved #{result.venues_moved} venues, #{result.events_moved} events. Deleted #{result.cities_deleted} duplicate cities."
          )
          |> load_duplicates()

        {:noreply, socket}

      {:error, reason} ->
        error_message =
          case reason do
            :source_city_not_found -> "One or more source cities not found"
            :cities_must_be_in_same_country -> "Cities must be in the same country"
            _ -> "Failed to merge cities: #{inspect(reason)}"
          end

        {:noreply, put_flash(socket, :error, error_message)}
    end
  end

  @impl true
  def handle_event("select_city", %{"id" => id}, socket) do
    city_id = String.to_integer(id)

    case CityManager.get_city(city_id) do
      nil ->
        socket = put_flash(socket, :error, "City not found")
        {:noreply, socket}

      city ->
        socket =
          socket
          |> assign(:selected_city, city)
          |> assign(:new_alternate_name, "")
          |> assign(:active_tab, "alternate_names")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_alternate_name", %{"name" => name}, socket) do
    city = socket.assigns.selected_city

    case CityManager.add_alternate_name(city, name) do
      {:ok, updated_city} ->
        socket =
          socket
          |> assign(:selected_city, updated_city |> Repo.preload(:country))
          |> assign(:new_alternate_name, "")
          |> put_flash(:info, "Alternate name \"#{name}\" added successfully")
          |> load_duplicates()

        {:noreply, socket}

      {:error, :empty_name} ->
        {:noreply, put_flash(socket, :error, "Alternate name cannot be empty")}

      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "This alternate name already exists")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add alternate name")}
    end
  end

  @impl true
  def handle_event("remove_alternate_name", %{"name" => name}, socket) do
    city = socket.assigns.selected_city

    case CityManager.remove_alternate_name(city, name) do
      {:ok, updated_city} ->
        socket =
          socket
          |> assign(:selected_city, updated_city |> Repo.preload(:country))
          |> put_flash(:info, "Alternate name \"#{name}\" removed successfully")
          |> load_duplicates()

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove alternate name")}
    end
  end

  @impl true
  def handle_event("close_city_panel", _params, socket) do
    socket =
      socket
      |> assign(:selected_city, nil)
      |> assign(:active_tab, "duplicates")

    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  # Private functions

  defp load_duplicates(socket) do
    duplicate_groups = CityManager.find_potential_duplicates()
    assign(socket, :duplicate_groups, duplicate_groups)
  end
end
