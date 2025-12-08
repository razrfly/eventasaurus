defmodule EventasaurusWeb.Admin.CityDuplicatesLive do
  @moduledoc """
  Admin page for managing city alternate names and detecting/merging duplicates.

  Features:
  - Detect potential duplicate cities
  - Merge duplicate cities
  - Add/remove alternate names
  - Pagination for large result sets
  - Collapsible groups for better UX
  - Search and filtering
  - Confidence scoring for prioritization
  - Data quality warnings
  - Scraper source tracking
  - Dismiss/ignore functionality
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusApp.Repo

  @per_page 10

  @impl true
  def mount(_params, _session, socket) do
    # Load countries for filter dropdown
    countries = CityManager.list_countries()

    socket =
      socket
      |> assign(:page_title, "City Duplicates & Alternate Names")
      |> assign(:duplicate_groups, [])
      |> assign(:all_duplicate_groups, [])
      |> assign(:selected_city, nil)
      |> assign(:new_alternate_name, "")
      |> assign(:loading, true)
      |> assign(:active_tab, "duplicates")
      |> assign(:detection_time_ms, nil)
      # Filtering
      |> assign(:search, "")
      |> assign(:country_filter, nil)
      |> assign(:sort_by, "confidence")
      |> assign(:countries, countries)
      |> assign(:show_suburbs, true)
      # Pagination
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:total_pages, 1)
      # Expanded groups tracking (set of group indices)
      |> assign(:expanded_groups, MapSet.new())
      # Dismissed groups (stored as MapSet of group "fingerprints")
      |> assign(:dismissed_groups, MapSet.new())
      # Confidence data cache (group fingerprint -> confidence data)
      |> assign(:confidence_cache, %{})
      # Sources cache (city_id -> sources list)
      |> assign(:sources_cache, %{})

    # Load duplicates asynchronously to avoid blocking mount
    send(self(), :load_duplicates)

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_duplicates, socket) do
    {time_us, all_groups} = :timer.tc(fn -> CityManager.find_potential_duplicates() end)
    time_ms = div(time_us, 1000)

    # Calculate confidence for all groups and cache it
    confidence_cache =
      all_groups
      |> Enum.with_index()
      |> Enum.map(fn {group, _idx} ->
        fingerprint = group_fingerprint(group)
        confidence = CityManager.calculate_group_confidence(group)
        {fingerprint, confidence}
      end)
      |> Map.new()

    socket =
      socket
      |> assign(:all_duplicate_groups, all_groups)
      |> assign(:confidence_cache, confidence_cache)
      |> assign(:loading, false)
      |> assign(:detection_time_ms, time_ms)
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  @impl true
  def handle_event("detect_duplicates", _params, socket) do
    send(self(), :load_duplicates)

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:detection_time_ms, nil)
      |> assign(:dismissed_groups, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"value" => search}, socket) do
    socket =
      socket
      |> assign(:search, search)
      |> assign(:page, 1)
      |> assign(:expanded_groups, MapSet.new())
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_country", %{"country_id" => country_id}, socket) do
    country_id = if country_id == "", do: nil, else: String.to_integer(country_id)

    socket =
      socket
      |> assign(:country_filter, country_id)
      |> assign(:page, 1)
      |> assign(:expanded_groups, MapSet.new())
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_by", %{"sort" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:page, 1)
      |> assign(:expanded_groups, MapSet.new())
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_suburbs", _params, socket) do
    socket =
      socket
      |> assign(:show_suburbs, not socket.assigns.show_suburbs)
      |> assign(:page, 1)
      |> assign(:expanded_groups, MapSet.new())
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_change", params, socket) do
    # Handle all filter changes from the form
    socket =
      socket
      |> maybe_update_country_filter(params)
      |> maybe_update_sort(params)
      |> maybe_update_show_suburbs(params)
      |> assign(:page, 1)
      |> assign(:expanded_groups, MapSet.new())
      |> apply_filters_and_sort()

    {:noreply, socket}
  end

  defp maybe_update_country_filter(socket, %{"country_id" => country_id}) do
    country_id = if country_id == "", do: nil, else: String.to_integer(country_id)
    assign(socket, :country_filter, country_id)
  end

  defp maybe_update_country_filter(socket, _params), do: socket

  defp maybe_update_sort(socket, %{"sort" => sort_by}) do
    assign(socket, :sort_by, sort_by)
  end

  defp maybe_update_sort(socket, _params), do: socket

  defp maybe_update_show_suburbs(socket, params) do
    # Checkbox sends "true" when checked, is absent when unchecked
    show_suburbs = Map.get(params, "show_suburbs") == "true"
    assign(socket, :show_suburbs, show_suburbs)
  end

  @impl true
  def handle_event("dismiss_group", %{"fingerprint" => fingerprint}, socket) do
    dismissed_groups = MapSet.put(socket.assigns.dismissed_groups, fingerprint)

    socket =
      socket
      |> assign(:dismissed_groups, dismissed_groups)
      |> apply_filters_and_sort()

    {:noreply, put_flash(socket, :info, "Group dismissed. It will reappear on next detection.")}
  end

  @impl true
  def handle_event("load_sources", %{"city_id" => city_id_str}, socket) do
    city_id = String.to_integer(city_id_str)

    # Check if already cached
    sources_cache = socket.assigns.sources_cache

    if Map.has_key?(sources_cache, city_id) do
      {:noreply, socket}
    else
      sources =
        CityManager.get_city_sources(city_id)
        |> Enum.map(fn {name, count} -> %{name: name, event_count: count} end)

      updated_cache = Map.put(sources_cache, city_id, sources)
      {:noreply, assign(socket, :sources_cache, updated_cache)}
    end
  end

  @impl true
  def handle_event("merge_cities", params, socket) do
    target_id = String.to_integer(params["target_id"])
    group_index = String.to_integer(params["group_index"])
    all_city_ids = String.split(params["source_ids"], ",") |> Enum.map(&String.to_integer/1)
    source_ids = Enum.reject(all_city_ids, &(&1 == target_id))
    add_as_alternates = params["add_as_alternates"] == "true"

    case CityManager.merge_cities(target_id, source_ids, add_as_alternates) do
      {:ok, result} ->
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
          |> reload_duplicates()

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
          |> reload_duplicates()

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

  defp reload_duplicates(socket) do
    all_groups = CityManager.find_potential_duplicates()

    confidence_cache =
      all_groups
      |> Enum.map(fn group ->
        fingerprint = group_fingerprint(group)
        confidence = CityManager.calculate_group_confidence(group)
        {fingerprint, confidence}
      end)
      |> Map.new()

    socket
    |> assign(:all_duplicate_groups, all_groups)
    |> assign(:confidence_cache, confidence_cache)
    |> apply_filters_and_sort()
  end

  defp apply_filters_and_sort(socket) do
    all_groups = socket.assigns.all_duplicate_groups
    search = socket.assigns.search |> String.downcase() |> String.trim()
    country_filter = socket.assigns.country_filter
    show_suburbs = socket.assigns.show_suburbs
    sort_by = socket.assigns.sort_by
    dismissed_groups = socket.assigns.dismissed_groups
    confidence_cache = socket.assigns.confidence_cache

    filtered_groups =
      all_groups
      |> Enum.reject(fn group ->
        # Filter out dismissed groups
        MapSet.member?(dismissed_groups, group_fingerprint(group))
      end)
      |> Enum.filter(fn group ->
        # Search filter
        matches_search =
          if search == "" do
            true
          else
            Enum.any?(group, fn city ->
              String.contains?(String.downcase(city.name), search)
            end)
          end

        # Country filter
        matches_country =
          if is_nil(country_filter) do
            true
          else
            Enum.any?(group, fn city -> city.country_id == country_filter end)
          end

        # Suburb filter
        matches_suburb_filter =
          if show_suburbs do
            true
          else
            confidence = Map.get(confidence_cache, group_fingerprint(group), %{})
            not Map.get(confidence, :is_likely_suburb, false)
          end

        matches_search and matches_country and matches_suburb_filter
      end)

    # Sort groups
    sorted_groups =
      case sort_by do
        "confidence" ->
          Enum.sort_by(filtered_groups, fn group ->
            confidence = Map.get(confidence_cache, group_fingerprint(group), %{})
            -Map.get(confidence, :score, 0)
          end)

        "venues" ->
          Enum.sort_by(filtered_groups, fn group ->
            -total_venues_in_group(group)
          end)

        "name" ->
          Enum.sort_by(filtered_groups, fn group ->
            anchor = get_anchor_city(group)
            String.downcase(anchor.name)
          end)

        _ ->
          filtered_groups
      end

    total_pages = max(1, ceil(length(sorted_groups) / socket.assigns.per_page))
    current_page = min(socket.assigns.page, total_pages)

    socket
    |> assign(:duplicate_groups, sorted_groups)
    |> assign(:total_pages, total_pages)
    |> assign(:page, current_page)
  end

  defp remove_group_from_list(socket, group_index) do
    # Remove from both filtered and all groups
    filtered_groups = socket.assigns.duplicate_groups
    removed_group = Enum.at(filtered_groups, group_index)

    # Remove from filtered list
    new_filtered = List.delete_at(filtered_groups, group_index)

    # Also remove from all groups list
    new_all =
      if removed_group do
        fingerprint = group_fingerprint(removed_group)
        Enum.reject(socket.assigns.all_duplicate_groups, fn g ->
          group_fingerprint(g) == fingerprint
        end)
      else
        socket.assigns.all_duplicate_groups
      end

    total_pages = max(1, ceil(length(new_filtered) / socket.assigns.per_page))
    current_page = socket.assigns.page
    new_page = min(current_page, total_pages)

    expanded_groups =
      socket.assigns.expanded_groups
      |> MapSet.delete(group_index)
      |> MapSet.to_list()
      |> Enum.map(fn idx -> if idx > group_index, do: idx - 1, else: idx end)
      |> MapSet.new()

    socket
    |> assign(:duplicate_groups, new_filtered)
    |> assign(:all_duplicate_groups, new_all)
    |> assign(:total_pages, total_pages)
    |> assign(:page, new_page)
    |> assign(:expanded_groups, expanded_groups)
  end

  # Generate a unique fingerprint for a group based on city IDs
  defp group_fingerprint(group) do
    group
    |> Enum.map(& &1.id)
    |> Enum.sort()
    |> Enum.join("-")
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

  @doc """
  Gets the confidence data for a group from the cache.
  """
  def get_group_confidence(confidence_cache, group) do
    Map.get(confidence_cache, group_fingerprint(group), %{score: 0, reasons: [], is_likely_suburb: false, data_quality_issues: []})
  end

  @doc """
  Formats a confidence score as a percentage string.
  """
  def format_confidence(score) when is_number(score) do
    "#{round(score * 100)}%"
  end

  def format_confidence(_), do: "N/A"

  @doc """
  Returns a CSS class for confidence badge based on score.
  """
  def confidence_badge_class(score) when is_number(score) do
    cond do
      score >= 0.7 -> "bg-red-100 text-red-800"
      score >= 0.4 -> "bg-yellow-100 text-yellow-800"
      true -> "bg-green-100 text-green-800"
    end
  end

  def confidence_badge_class(_), do: "bg-gray-100 text-gray-800"

  @doc """
  Returns a human-readable label for confidence level.
  """
  def confidence_label(score) when is_number(score) do
    cond do
      score >= 0.7 -> "Likely Duplicate"
      score >= 0.4 -> "Needs Review"
      true -> "Likely Suburbs"
    end
  end

  def confidence_label(_), do: "Unknown"

  @doc """
  Formats data quality issues as human-readable strings.
  """
  def format_data_quality_issue("postcode_in_name"), do: "Postcode in name"
  def format_data_quality_issue("state_abbreviation"), do: "State abbreviation"
  def format_data_quality_issue("short_with_numbers"), do: "Short name with numbers"
  def format_data_quality_issue(issue), do: issue
end
