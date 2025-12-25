defmodule EventasaurusWeb.CityLive.Search do
  @moduledoc """
  LiveView for city-specific search.
  """
  use EventasaurusWeb, :live_view

  alias Eventasaurus.CDN
  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusDiscovery.Categories

  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    city = Locations.get_city_by_slug!(city_slug)

    # Get language from connect params (safe nil handling) or default to English
    params = get_connect_params(socket) || %{}
    language = params["locale"] || "en"

    socket =
      socket
      |> assign(:city, city)
      |> assign(:language, language)
      |> assign(:page_title, "Search Events in #{city.name}")
      |> assign(:view_mode, "grid")
      |> assign(:filters, default_filters())
      |> assign(:categories, Categories.list_categories())
      |> assign(:filter_facets, %{})
      |> assign(:show_filters, false)
      |> assign(:loading, false)
      # Flag to auto-focus search on load
      |> assign(:search_focused, true)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_params_to_filters(params)
      |> fetch_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    filters = Map.put(socket.assigns.filters, :search, search_term)

    socket =
      socket
      |> assign(:filters, filters)
      |> fetch_events()
      |> push_patch(
        to: build_path(%{socket | assigns: Map.put(socket.assigns, :filters, filters)})
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    filters = Map.put(socket.assigns.filters, :search, nil)

    socket =
      socket
      |> assign(:filters, filters)
      |> fetch_events()
      |> push_patch(
        to: build_path(%{socket | assigns: Map.put(socket.assigns, :filters, filters)})
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter_params}, socket) do
    current_filters = socket.assigns.filters

    new_filters = %{
      categories: parse_id_list(filter_params["categories"]),
      radius_km: parse_integer(filter_params["radius_km"]) || current_filters.radius_km,
      start_date: parse_date(filter_params["start_date"]),
      end_date: parse_date(filter_params["end_date"]),
      min_price: parse_decimal(filter_params["min_price"]),
      max_price: parse_decimal(filter_params["max_price"]),
      sort_by: parse_sort(filter_params["sort_by"]),
      sort_order: :asc,
      search: current_filters.search,
      page: 1,
      page_size: current_filters.page_size
    }

    socket =
      socket
      |> assign(:filters, new_filters)
      |> push_patch(
        to: build_path(%{socket | assigns: Map.put(socket.assigns, :filters, new_filters)})
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_view", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, mode)}
  end

  @impl true
  def handle_event("toggle_filters", _params, socket) do
    {:noreply, assign(socket, :show_filters, !socket.assigns.show_filters)}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    filters = Map.put(socket.assigns.filters, :page, page)

    socket =
      socket
      |> assign(:filters, filters)
      |> fetch_events()
      |> push_patch(
        to: build_path(%{socket | assigns: Map.put(socket.assigns, :filters, filters)})
      )

    {:noreply, socket}
  end

  defp default_filters do
    %{
      categories: [],
      radius_km: 25,
      start_date: DateTime.utc_now(),
      end_date: DateTime.add(DateTime.utc_now(), 90, :day),
      min_price: nil,
      max_price: nil,
      sort_by: :date,
      sort_order: :asc,
      search: nil,
      page: 1,
      # Divisible by 3 for grid layout
      page_size: 60
    }
  end

  defp apply_params_to_filters(socket, params) do
    filters = %{
      socket.assigns.filters
      | search: params["search"] || socket.assigns.filters.search,
        page: parse_integer(params["page"]) || socket.assigns.filters.page,
        radius_km: parse_integer(params["radius"]) || socket.assigns.filters.radius_km,
        sort_by: parse_sort(params["sort"]) || socket.assigns.filters.sort_by
    }

    assign(socket, :filters, filters)
  end

  defp fetch_events(socket) do
    city = socket.assigns.city
    filters = socket.assigns.filters
    language = socket.assigns.language

    # Get city coordinates for radius filtering
    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    # Build query filters using PublicEventsEnhanced for consistency
    query_filters =
      Map.merge(filters, %{
        language: language,
        center_lat: lat,
        center_lng: lng,
        radius_km: filters[:radius_km] || 50,
        search: filters[:search],
        categories: filters[:categories],
        sort_by: filters[:sort_by],
        sort_order: :asc,
        page: filters[:page] || 1,
        page_size: filters[:page_size] || 60,
        # Phase 3.1: Pass browsing city for Unsplash fallback enrichment
        browsing_city_id: city.id
      })

    alias EventasaurusDiscovery.PublicEventsEnhanced

    # Use PublicEventsEnhanced to get events with all filters applied at DB level
    events =
      if lat && lng do
        events = PublicEventsEnhanced.list_events(query_filters)

        # Batch fetch primary categories to avoid N+1 queries
        event_ids = Enum.map(events, & &1.id)
        primary_category_map = fetch_primary_category_ids(event_ids)

        # Add primary_category_id to each event for category display
        Enum.map(events, fn event ->
          Map.put(event, :primary_category_id, Map.get(primary_category_map, event.id))
        end)
      else
        []
      end

    # Build pagination metadata
    page = filters[:page] || 1
    page_size = filters[:page_size] || 60
    has_next = length(events) == page_size

    # Estimate total entries based on current page
    total_entries =
      if has_next do
        # Estimate based on current page having full results
        page * page_size + 1
      else
        # Current page is the last page
        (page - 1) * page_size + length(events)
      end

    total_pages = ceil(total_entries / page_size)

    pagination = %Pagination{
      entries: events,
      page_number: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }

    assign(socket,
      events: events,
      pagination: pagination,
      total_events: length(events)
    )
  end

  # Sorting is now handled at the database level via PublicEventsEnhanced

  defp build_path(socket) do
    filters = socket.assigns.filters
    city = socket.assigns.city

    query_params = []

    query_params =
      if filters.search, do: [{"search", filters.search} | query_params], else: query_params

    query_params =
      if filters.page > 1, do: [{"page", filters.page} | query_params], else: query_params

    query_params =
      if filters.radius_km != 25,
        do: [{"radius", filters.radius_km} | query_params],
        else: query_params

    query_params =
      if filters.sort_by != :date,
        do: [{"sort", Atom.to_string(filters.sort_by)} | query_params],
        else: query_params

    ~p"/c/#{city.slug}/search?#{query_params}"
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_id_list(nil), do: []

  defp parse_id_list(ids) when is_binary(ids) do
    ids
    |> String.split(",", trim: true)
    |> Enum.map(&String.to_integer/1)
  end

  defp parse_id_list(ids) when is_list(ids), do: ids

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        # Convert to DateTime at start of day for consistency with defaults
        DateTime.new!(date, ~T[00:00:00])

      _ ->
        nil
    end
  end

  defp parse_decimal(nil), do: nil

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      _ -> nil
    end
  end

  defp parse_sort(nil), do: :starts_at

  defp parse_sort(value) when is_binary(value) do
    case value do
      "starts_at" -> :starts_at
      "price" -> :price
      "title" -> :title
      "relevance" -> :relevance
      _ -> :starts_at
    end
  end

  defp parse_sort(value) when is_atom(value), do: value

  defp has_ticket_url?(event) do
    case event.sources do
      [] ->
        false

      sources when is_list(sources) ->
        Enum.any?(sources, fn source ->
          source.source_url && source.source_url != ""
        end)

      _ ->
        false
    end
  end

  # Category helper functions
  defp get_primary_category(event) do
    case event[:primary_category_id] do
      nil -> nil
      cat_id -> Enum.find(event.categories || [], &(&1.id == cat_id))
    end
  end

  defp fetch_primary_category_ids(event_ids) when is_list(event_ids) and event_ids != [] do
    import Ecto.Query
    alias EventasaurusApp.Repo

    Repo.all(
      from(pec in "public_event_categories",
        where: pec.event_id in ^event_ids and pec.is_primary == true,
        select: {pec.event_id, pec.category_id}
      )
    )
    |> Map.new()
  end

  defp fetch_primary_category_ids(_), do: %{}
end
