defmodule EventasaurusWeb.Admin.CityDuplicatesLive do
  @moduledoc """
  Admin page for managing city alternate names and detecting/merging duplicates.

  Features:
  - Detect potential duplicate cities
  - Merge duplicate cities
  - Add/remove alternate names
  - Pagination for large result sets
  - Collapsible groups for better UX
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusApp.Repo

  @per_page 10

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
      # Pagination
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:total_pages, 1)
      # Expanded groups tracking (set of group indices)
      |> assign(:expanded_groups, MapSet.new())

    # Load duplicates asynchronously to avoid blocking mount
    send(self(), :load_duplicates)

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_duplicates, socket) do
    {time_us, duplicate_groups} = :timer.tc(fn -> CityManager.find_potential_duplicates() end)
    time_ms = div(time_us, 1000)

    total_pages = max(1, ceil(length(duplicate_groups) / socket.assigns.per_page))

    socket =
      socket
      |> assign(:duplicate_groups, duplicate_groups)
      |> assign(:loading, false)
      |> assign(:detection_time_ms, time_ms)
      |> assign(:total_pages, total_pages)
      |> assign(:page, 1)
      |> assign(:expanded_groups, MapSet.new())

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
    group_index = String.to_integer(params["group_index"])
    all_city_ids = String.split(params["source_ids"], ",") |> Enum.map(&String.to_integer/1)
    # Filter out the target city from the source list
    source_ids = Enum.reject(all_city_ids, &(&1 == target_id))
    add_as_alternates = params["add_as_alternates"] == "true"

    case CityManager.merge_cities(target_id, source_ids, add_as_alternates) do
      {:ok, result} ->
        # Remove merged group from memory instead of full reload
        socket = remove_group_from_list(socket, group_index)

        socket =
          socket
          |> put_flash(
            :info,
            "Successfully merged cities! Moved #{result.venues_moved} venues, #{result.events_moved} events. Deleted #{result.cities_deleted} duplicate cities."
          )

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

  @impl true
  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = String.to_integer(page)
    # Reset expanded groups when changing pages
    socket =
      socket
      |> assign(:page, page)
      |> assign(:expanded_groups, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_group", %{"index" => index}, socket) do
    index = String.to_integer(index)
    expanded_groups = socket.assigns.expanded_groups

    expanded_groups =
      if MapSet.member?(expanded_groups, index) do
        MapSet.delete(expanded_groups, index)
      else
        MapSet.put(expanded_groups, index)
      end

    {:noreply, assign(socket, :expanded_groups, expanded_groups)}
  end

  # Private functions

  defp load_duplicates(socket) do
    duplicate_groups = CityManager.find_potential_duplicates()
    total_pages = max(1, ceil(length(duplicate_groups) / socket.assigns.per_page))

    socket
    |> assign(:duplicate_groups, duplicate_groups)
    |> assign(:total_pages, total_pages)
  end

  defp remove_group_from_list(socket, group_index) do
    duplicate_groups = List.delete_at(socket.assigns.duplicate_groups, group_index)
    total_pages = max(1, ceil(length(duplicate_groups) / socket.assigns.per_page))

    # Adjust current page if we're now past the last page
    current_page = socket.assigns.page
    new_page = min(current_page, total_pages)

    # Remove this group from expanded set and adjust indices
    expanded_groups =
      socket.assigns.expanded_groups
      |> MapSet.delete(group_index)
      |> MapSet.to_list()
      |> Enum.map(fn idx -> if idx > group_index, do: idx - 1, else: idx end)
      |> MapSet.new()

    socket
    |> assign(:duplicate_groups, duplicate_groups)
    |> assign(:total_pages, total_pages)
    |> assign(:page, new_page)
    |> assign(:expanded_groups, expanded_groups)
  end

  @doc """
  Gets the current page of duplicate groups based on pagination settings.
  """
  def paginated_groups(duplicate_groups, page, per_page) do
    duplicate_groups
    |> Enum.drop((page - 1) * per_page)
    |> Enum.take(per_page)
  end

  @doc """
  Gets the "anchor" city for a group - the one with the most venues.
  This is used to give the group a meaningful name.
  """
  def get_anchor_city(group) when is_list(group) and length(group) > 0 do
    Enum.max_by(group, & &1.venue_count, fn -> hd(group) end)
  end

  @doc """
  Calculates the total venue count for a group of cities.
  """
  def total_venues_in_group(group) when is_list(group) do
    Enum.reduce(group, 0, fn city, acc -> acc + (city.venue_count || 0) end)
  end

  @doc """
  Generates a pagination range with ellipsis for large page counts.
  """
  def pagination_range(_current_page, total_pages) when total_pages <= 7 do
    Enum.to_list(1..total_pages)
  end

  def pagination_range(current_page, total_pages) do
    pages =
      [1, current_page - 1, current_page, current_page + 1, total_pages]
      |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
      |> Enum.uniq()
      |> Enum.sort()

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
