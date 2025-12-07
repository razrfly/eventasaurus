defmodule EventasaurusWeb.Admin.CityIndexLive do
  @moduledoc """
  Admin page for managing cities.

  Allows listing, searching, filtering, and deleting cities.
  """
  use EventasaurusWeb, :live_view

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Workers.UnsplashCityRefreshWorker
  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Locations.Country

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    countries = Repo.replica().all(from(c in Country, order_by: c.name))

    socket =
      socket
      |> assign(:page_title, "Cities")
      |> assign(:countries, countries)
      |> assign(:search, "")
      |> assign(:country_filter, nil)
      |> assign(:discovery_filter, nil)
      |> assign(:sort_by, "name")
      |> assign(:sort_dir, "asc")
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:total_count, 0)
      |> assign(:total_pages, 1)
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
      |> assign(:page, parse_page(params["page"]))
      |> load_cities()

    {:noreply, socket}
  end

  defp parse_page(nil), do: 1

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {p, _} when p > 0 -> p
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    # Reset to page 1 when search changes
    params = build_params(socket, %{search: search, page: 1})
    {:noreply, push_patch(socket, to: ~p"/admin/cities?#{params}")}
  end

  @impl true
  def handle_event("filter_country", %{"country_id" => country_id}, socket) do
    country_id = if country_id == "", do: nil, else: country_id
    # Reset to page 1 when filter changes
    params = build_params(socket, %{country_id: country_id, page: 1})
    {:noreply, push_patch(socket, to: ~p"/admin/cities?#{params}")}
  end

  @impl true
  def handle_event("filter_discovery", %{"discovery_enabled" => discovery}, socket) do
    discovery = if discovery == "", do: nil, else: discovery
    # Reset to page 1 when filter changes
    params = build_params(socket, %{discovery_enabled: discovery, page: 1})
    {:noreply, push_patch(socket, to: ~p"/admin/cities?#{params}")}
  end

  @impl true
  def handle_event("go_to_page", %{"page" => page}, socket) do
    params = build_params(socket, %{page: page})
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

    # Reset to page 1 when sort changes
    params = build_params(socket, %{sort_by: sort_by, sort_dir: sort_dir, page: 1})
    {:noreply, push_patch(socket, to: ~p"/admin/cities?#{params}")}
  end

  @impl true
  def handle_event("delete_orphaned", _params, socket) do
    case CityManager.delete_orphaned_cities() do
      {:ok, count} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Successfully deleted #{count} orphaned #{if count == 1, do: "city", else: "cities"}"
          )
          |> load_cities()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to delete orphaned cities: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh_images", %{"id" => id}, socket) do
    city_id = String.to_integer(id)

    case Repo.replica().get(City, city_id) do
      nil ->
        socket = put_flash(socket, :error, "City not found")
        {:noreply, socket}

      city ->
        # Queue refresh job immediately
        %{city_id: city.id}
        |> UnsplashCityRefreshWorker.new()
        |> Oban.insert()

        socket =
          socket
          |> put_flash(:info, "Queued Unsplash image refresh for #{city.name}")
          |> load_cities()

        {:noreply, socket}
    end
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
      sort_dir: socket.assigns.sort_dir,
      page: socket.assigns.page,
      per_page: socket.assigns.per_page
    }

    cities = CityManager.list_cities_with_venue_counts(filters)
    total_count = CityManager.count_cities(filters)
    orphaned_count = CityManager.count_orphaned_cities()
    total_pages = max(1, ceil(total_count / socket.assigns.per_page))

    socket
    |> assign(:cities, cities)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
    |> assign(:orphaned_count, orphaned_count)
  end

  defp build_params(socket, updates) do
    page = updates[:page] || socket.assigns.page

    %{
      search: updates[:search] || socket.assigns.search,
      country_id: updates[:country_id] || socket.assigns.country_filter,
      discovery_enabled: updates[:discovery_enabled] || socket.assigns.discovery_filter,
      sort_by: updates[:sort_by] || socket.assigns.sort_by,
      sort_dir: updates[:sort_dir] || socket.assigns.sort_dir,
      page: if(page > 1, do: page, else: nil)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
    |> Map.new()
  end

  @doc """
  Generates a list of page numbers to display with ellipsis for large page counts.

  Shows first page, last page, current page, and 1 page on each side of current.
  Uses :ellipsis atom to indicate gaps.

  ## Examples

      iex> pagination_range(1, 5)
      [1, 2, 3, 4, 5]

      iex> pagination_range(5, 10)
      [1, :ellipsis, 4, 5, 6, :ellipsis, 10]
  """
  def pagination_range(_current_page, total_pages) when total_pages <= 7 do
    Enum.to_list(1..total_pages)
  end

  def pagination_range(current_page, total_pages) do
    # Always show: first, last, current, current-1, current+1
    pages =
      [1, current_page - 1, current_page, current_page + 1, total_pages]
      |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
      |> Enum.uniq()
      |> Enum.sort()

    # Add ellipsis where there are gaps
    pages
    |> Enum.reduce({[], 0}, fn page, {acc, prev} ->
      if prev > 0 and page - prev > 1 do
        {acc ++ [:ellipsis, page], page}
      else
        {acc ++ [page], page}
      end
    end)
    |> elem(0)
  end
end
