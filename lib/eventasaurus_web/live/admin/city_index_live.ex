defmodule EventasaurusWeb.Admin.CityIndexLive do
  @moduledoc """
  Admin page for managing cities.

  Allows listing, searching, filtering, and deleting cities.
  """
  use EventasaurusWeb, :live_view

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusDiscovery.Locations.Country

  @impl true
  def mount(_params, _session, socket) do
    countries = Repo.all(from(c in Country, order_by: c.name))

    socket =
      socket
      |> assign(:page_title, "Cities")
      |> assign(:countries, countries)
      |> assign(:search, "")
      |> assign(:country_filter, nil)
      |> assign(:discovery_filter, nil)
      |> assign(:sort_by, "name")
      |> assign(:sort_dir, "asc")
      |> load_cities()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:search, params["search"] || "")
      |> assign(:country_filter, params["country_id"])
      |> assign(:discovery_filter, params["discovery_enabled"])
      |> assign(:sort_by, params["sort_by"] || "name")
      |> assign(:sort_dir, params["sort_dir"] || "asc")
      |> load_cities()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = build_params(socket, %{search: search})
    {:noreply, push_patch(socket, to: ~p"/admin/cities?#{params}")}
  end

  @impl true
  def handle_event("filter_country", %{"country_id" => country_id}, socket) do
    country_id = if country_id == "", do: nil, else: country_id
    params = build_params(socket, %{country_id: country_id})
    {:noreply, push_patch(socket, to: ~p"/admin/cities?#{params}")}
  end

  @impl true
  def handle_event("filter_discovery", %{"discovery_enabled" => discovery}, socket) do
    discovery = if discovery == "", do: nil, else: discovery
    params = build_params(socket, %{discovery_enabled: discovery})
    {:noreply, push_patch(socket, to: ~p"/admin/cities?#{params}")}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) do
    {sort_by, sort_dir} =
      if socket.assigns.sort_by == column do
        # Toggle direction if same column
        {column, if(socket.assigns.sort_dir == "asc", do: "desc", else: "asc")}
      else
        # New column, default to asc
        {column, "asc"}
      end

    params = build_params(socket, %{sort_by: sort_by, sort_dir: sort_dir})
    {:noreply, push_patch(socket, to: ~p"/admin/cities?#{params}")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    city_id = String.to_integer(id)

    case CityManager.delete_city(city_id) do
      {:ok, city} ->
        socket =
          socket
          |> put_flash(:info, "City \"#{city.name}\" deleted successfully")
          |> load_cities()

        {:noreply, socket}

      {:error, :has_venues} ->
        socket =
          put_flash(
            socket,
            :error,
            "Cannot delete city with venues. Please delete or reassign venues first."
          )

        {:noreply, socket}

      {:error, _changeset} ->
        socket = put_flash(socket, :error, "Failed to delete city")
        {:noreply, socket}
    end
  end

  # Private functions

  defp load_cities(socket) do
    filters = %{
      search: socket.assigns.search,
      country_id: socket.assigns.country_filter,
      discovery_enabled: socket.assigns.discovery_filter,
      sort_by: socket.assigns.sort_by,
      sort_dir: socket.assigns.sort_dir
    }

    cities = CityManager.list_cities_with_venue_counts(filters)
    assign(socket, :cities, cities)
  end

  defp build_params(socket, updates) do
    %{
      search: updates[:search] || socket.assigns.search,
      country_id: updates[:country_id] || socket.assigns.country_filter,
      discovery_enabled: updates[:discovery_enabled] || socket.assigns.discovery_filter,
      sort_by: updates[:sort_by] || socket.assigns.sort_by,
      sort_dir: updates[:sort_dir] || socket.assigns.sort_dir
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
    |> Map.new()
  end
end
