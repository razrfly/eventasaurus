defmodule EventasaurusWeb.CityLive.Index do
  @moduledoc """
  LiveView for city-based event discovery pages.

  Displays events within a configurable radius of a city's center,
  using the city's dynamically calculated coordinates.
  """

  use EventasaurusWeb, :live_view
  require Logger

  import Ecto.Query, only: [from: 2]

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusDiscovery.Categories
  alias EventasaurusWeb.Components.OpenGraphComponent
  alias EventasaurusWeb.Live.Helpers.EventFilters
  alias EventasaurusWeb.Helpers.LanguageDiscovery
  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.JsonLd.CitySchema
  alias Eventasaurus.SocialCards.UrlBuilder
  alias EventasaurusWeb.Cache.CityPageCache

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.Components.EventListing

  on_mount {EventasaurusWeb.Live.LanguageHooks, :attach_language_handler}

  @default_radius_km 50

  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/activities")}

      city ->
        if city.latitude && city.longitude do
          # Get language from connect params (safe nil handling) or default to English
          params = get_connect_params(socket) || %{}
          language = params["locale"] || socket.assigns[:language] || "en"

          # Capture request URI for proper URL generation (ngrok support)
          raw_uri = get_connect_info(socket, :uri)

          request_uri =
            cond do
              match?(%URI{}, raw_uri) -> raw_uri
              is_binary(raw_uri) -> URI.parse(raw_uri)
              true -> nil
            end

          # STAGED LOADING: Initialize with loading state, defer expensive operations
          # This prevents mount timeout and provides fast initial render
          # Note: handle_params will immediately follow and set real values from URL
          {:ok,
           socket
           |> assign(:city, city)
           |> assign(:city_slug, city_slug)
           |> assign(:language, language)
           |> assign(:request_uri, request_uri)
           # Initialize with empty/loading states - will be populated by handle_info
           |> assign(:available_languages, ["en"])
           |> assign(:radius_km, @default_radius_km)
           |> assign(:view_mode, "grid")
           |> assign(:filters, %{page: 1, page_size: 30})
           |> assign(:show_filters, false)
           |> assign(:loading, true)
           |> assign(:events_loading, true)
           |> assign(:total_events, 0)
           |> assign(:all_events_count, 0)
           |> assign(:categories, [])
           |> assign(:events, [])
           |> assign(:open_graph, "")
           |> assign(:pagination, %Pagination{
             entries: [],
             page_number: 1,
             page_size: 30,
             total_entries: 0,
             total_pages: 0
           })
           |> assign(:active_date_range, nil)
           |> assign(:date_range_counts, %{})
           # Aggregation: group movies with multiple showtimes together
           |> assign(:aggregate, true)
           # Track that we're in deferred loading mode - handle_params will update filters from URL
           |> assign(:deferred_loading, true)
           # Prevent concurrent/duplicate fetch_events calls (fixes double-fetch bug)
           |> assign(:fetch_in_progress, false)
           |> defer_expensive_loading()}
        else
          {:ok,
           socket
           |> put_flash(:error, "City location data is being processed. Please try again later.")
           |> push_navigate(to: ~p"/activities")}
        end
    end
  end

  # Defer expensive operations to handle_info for staged loading
  defp defer_expensive_loading(socket) do
    if connected?(socket) do
      send(self(), :load_initial_data)
    end

    socket
  end

  @impl true
  def handle_info(:load_initial_data, socket) do
    # DEBUG: Artificial delay to visualize staged loading (remove in production)
    if Application.get_env(:eventasaurus, :debug_staged_loading, false) do
      Process.sleep(500)
    end

    # STAGE 1: Load lightweight data (categories, languages, meta tags)
    city = socket.assigns.city
    city_slug = socket.assigns.city_slug
    request_uri = socket.assigns.request_uri

    # Get dynamically available languages for this city
    available_languages =
      try do
        LanguageDiscovery.get_available_languages_for_city(city_slug)
      rescue
        e ->
          Logger.warning(
            "Language discovery failed for city_slug=#{city_slug}: #{Exception.message(e)}"
          )

          ["en"]
      end

    # Get categories (cached)
    categories = CityPageCache.get_categories(&Categories.list_categories/0)

    # Generate city stats and meta tags
    city_stats = fetch_city_stats(city)
    json_ld = CitySchema.generate(city, city_stats)

    # Generate social card URL path
    city_with_stats = Map.put(city, :stats, city_stats)
    social_card_path = UrlBuilder.build_path(:city, city_with_stats)

    # Generate Open Graph meta tags
    og_tags = build_city_open_graph(city, city_stats, social_card_path, request_uri)

    socket =
      socket
      |> assign(:available_languages, available_languages)
      |> assign(:categories, categories)
      |> assign(:open_graph, og_tags)
      |> SEOHelpers.assign_meta_tags(
        title: page_title(city),
        description: meta_description(city),
        image: social_card_path,
        type: "website",
        canonical_path: "/c/#{city.slug}",
        json_ld: json_ld,
        request_uri: request_uri
      )
      |> assign(:loading, false)

    # Trigger events loading (the expensive operation)
    send(self(), :load_events)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_events, socket) do
    # Guard: Skip if fetch is already in progress (prevents double-fetch bug)
    if socket.assigns[:fetch_in_progress] do
      {:noreply, socket}
    else
      # DEBUG: Artificial delay to visualize staged loading (remove in production)
      if Application.get_env(:eventasaurus, :debug_staged_loading, false) do
        Process.sleep(2000)
      end

      # Mark fetch as in progress before starting
      socket = assign(socket, :fetch_in_progress, true)

      # STAGE 2: Load events (expensive geographic query)
      socket =
        try do
          socket
          |> fetch_events()
          |> fetch_nearby_cities()
          |> assign(:events_loading, false)
          # Clear deferred_loading flag - initial loading is complete
          |> assign(:deferred_loading, false)
          |> assign(:fetch_in_progress, false)
        rescue
          e ->
            Logger.error(
              "Failed to load events for city #{socket.assigns.city.slug}: #{inspect(e)}"
            )

            socket
            |> assign(:events, [])
            |> assign(:events_loading, false)
            |> assign(:deferred_loading, false)
            |> assign(:fetch_in_progress, false)
            |> assign(:total_events, 0)
        end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:load_filtered_events, socket) do
    # Guard: Skip if fetch is already in progress (prevents double-fetch bug)
    if socket.assigns[:fetch_in_progress] do
      {:noreply, socket}
    else
      # DEBUG: Artificial delay to visualize staged loading on filter changes
      if Application.get_env(:eventasaurus, :debug_staged_loading, false) do
        Process.sleep(2000)
      end

      # Mark fetch as in progress before starting
      socket = assign(socket, :fetch_in_progress, true)

      # Load events with current filters (expensive geographic query)
      socket =
        try do
          socket
          |> fetch_events()
          |> assign(:events_loading, false)
          |> assign(:fetch_in_progress, false)
        rescue
          e ->
            Logger.error(
              "Failed to load filtered events for city #{socket.assigns.city.slug}: #{inspect(e)}"
            )

            socket
            |> assign(:events, [])
            |> assign(:events_loading, false)
            |> assign(:fetch_in_progress, false)
            |> assign(:total_events, 0)
        end

      {:noreply, socket}
    end
  end

  # Language change is handled by LanguageHooks via on_mount
  # This callback handles the reload after language changes
  @impl true
  def handle_info({:language_changed, _language}, socket) do
    # ASYNC: Show skeleton immediately, load events in background
    socket = assign(socket, :events_loading, true)
    send(self(), :load_filtered_events)
    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Skip in two cases:
    # 1. deferred_loading = true: Initial mount is using staged loading pattern
    #    BUT we still need to capture the URL params for when :load_events runs
    # 2. events_loading = true AND NOT deferred_loading: A handle_event triggered
    #    push_patch and sent :load_filtered_events message
    cond do
      socket.assigns[:deferred_loading] == true ->
        # Initial staged loading - capture URL params for :load_events to use
        # This ensures direct URL navigation (e.g., ?page=7) respects URL state
        socket = apply_url_params_for_deferred_load(socket, params)
        {:noreply, socket}

      socket.assigns[:events_loading] == true ->
        # handle_event already set filters and is loading events asynchronously
        # Don't touch filters or fetch events
        {:noreply, socket}

      true ->
        # Normal navigation (e.g., direct URL access, browser back/forward)
        # Apply params and fetch events
        socket =
          socket
          |> apply_params_to_filters(params)
          |> fetch_events()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    filters = Map.put(socket.assigns.filters, :search, search_term)

    # ASYNC: Show skeleton immediately, load events in background
    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:events_loading, true)
      |> push_patch(to: build_path(socket, filters))

    send(self(), :load_filtered_events)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    filters = Map.put(socket.assigns.filters, :search, nil)

    # ASYNC: Show skeleton immediately, load events in background
    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:events_loading, true)
      |> push_patch(to: build_path(socket, filters))

    send(self(), :load_filtered_events)
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter_params}, socket) do
    radius_km = parse_integer(filter_params["radius"]) || @default_radius_km

    # Update existing filters instead of creating new map
    # This preserves date filters (start_date, end_date, show_past)
    filters =
      socket.assigns.filters
      |> Map.put(:categories, parse_id_list(filter_params["categories"]))
      |> Map.put(:radius_km, radius_km)
      |> Map.put(:sort_by, parse_sort(filter_params["sort_by"]))
      |> Map.put(:sort_order, :asc)
      |> Map.put(:page, 1)

    # ASYNC: Show skeleton immediately, load events in background
    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:radius_km, radius_km)
      |> assign(:events_loading, true)
      |> push_patch(to: build_path(socket, filters))

    send(self(), :load_filtered_events)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    # Clear all filters including date filters
    cleared_filters = %{
      search: nil,
      categories: [],
      start_date: nil,
      end_date: nil,
      radius_km: @default_radius_km,
      sort_by: :starts_at,
      sort_order: :asc,
      page: 1,
      page_size: 30,
      show_past: false
    }

    # ASYNC: Show skeleton immediately, load events in background
    socket =
      socket
      |> assign(:filters, cleared_filters)
      |> assign(:radius_km, @default_radius_km)
      |> assign(:active_date_range, nil)
      |> assign(:events_loading, true)
      |> push_patch(to: build_path(socket, cleared_filters))

    send(self(), :load_filtered_events)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_filters", _params, socket) do
    {:noreply, update(socket, :show_filters, &(!&1))}
  end

  @impl true
  def handle_event("change_view", %{"view" => view_mode}, socket) do
    {:noreply, assign(socket, :view_mode, view_mode)}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    updated_filters = Map.put(socket.assigns.filters, :page, page)

    # ASYNC: Show skeleton immediately, load events in background
    socket =
      socket
      |> assign(:filters, updated_filters)
      |> assign(:events_loading, true)
      |> push_patch(to: build_path(socket, updated_filters))

    send(self(), :load_filtered_events)
    {:noreply, socket}
  end

  def handle_event("quick_date_filter", %{"range" => range}, socket) do
    # Use EventFilters security validation instead of String.to_existing_atom
    case EventFilters.parse_quick_range(range) do
      {:ok, range_atom} ->
        # Apply the date filter using shared helper
        filters = EventFilters.apply_quick_date_filter(socket.assigns.filters, range_atom)

        # Set active_date_range (nil for :all, atom for others)
        active_date_range = if range_atom == :all, do: nil, else: range_atom

        # ASYNC: Show skeleton immediately, load events in background
        socket =
          socket
          |> assign(:filters, filters)
          |> assign(:active_date_range, active_date_range)
          |> assign(:events_loading, true)
          |> push_patch(to: build_path(socket, filters))

        send(self(), :load_filtered_events)
        {:noreply, socket}

      :error ->
        # Invalid range - ignore the request
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_date_filter", _params, socket) do
    # Use EventFilters shared helper
    filters = EventFilters.clear_date_filter(socket.assigns.filters)

    # ASYNC: Show skeleton immediately, load events in background
    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:active_date_range, nil)
      |> assign(:events_loading, true)
      |> push_patch(to: build_path(socket, filters))

    send(self(), :load_filtered_events)
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_category", %{"id" => category_id}, socket) do
    case Integer.parse(category_id) do
      {id, _} ->
        current_categories = socket.assigns.filters.categories || []
        updated_categories = Enum.reject(current_categories, &(&1 == id))

        filters = Map.put(socket.assigns.filters, :categories, updated_categories)

        # ASYNC: Show skeleton immediately, load events in background
        socket =
          socket
          |> assign(:filters, filters)
          |> assign(:events_loading, true)
          |> push_patch(to: build_path(socket, filters))

        send(self(), :load_filtered_events)
        {:noreply, socket}

      :error ->
        # Invalid category ID - ignore the request
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    sort_atom = parse_sort(sort_by)

    filters =
      socket.assigns.filters
      |> Map.put(:sort_by, sort_atom)
      |> Map.put(:page, 1)

    # ASYNC: Show skeleton immediately, load events in background
    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:events_loading, true)
      |> push_patch(to: build_path(socket, filters))

    send(self(), :load_filtered_events)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header with Title and Controls -->
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-3xl font-bold text-gray-900">
            <%= gettext("Events in %{city}", city: @city.name) %>
          </h1>
          <div class="flex items-center gap-4">
            <!-- Language Switcher -->
            <.language_switcher
              available_languages={@available_languages}
              current_language={@language}
            />

            <!-- Sort Controls -->
            <.sort_controls sort_by={@filters.sort_by} show_popularity={true} />

            <!-- View Mode Toggle -->
            <.view_toggle view_mode={@view_mode} />

            <!-- Filter Toggle -->
            <button
              phx-click="toggle_filters"
              class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 flex items-center space-x-2"
            >
              <Heroicons.funnel class="w-5 h-5" />
              <span>Filters</span>
              <%= if EventFilters.active_filter_count(@filters, 50) > 0 do %>
                <span class="ml-2 bg-blue-700 px-2 py-0.5 rounded-full text-xs">
                  <%= EventFilters.active_filter_count(@filters, 50) %>
                </span>
              <% end %>
            </button>
          </div>
        </div>

        <!-- Filters Panel (Expandable) -->
        <div :if={@show_filters} class="mb-6">
          <.filter_panel
            filters={@filters}
            radius_km={@radius_km}
            categories={@categories}
          />
        </div>

        <!-- Search Bar -->
        <.search_bar filters={@filters} />

        <!-- Quick Date Filters -->
        <div class="mt-4">
          <.quick_date_filters
            active_date_range={@active_date_range}
            date_range_counts={@date_range_counts}
            all_events_count={@all_events_count}
          />
        </div>

        <!-- Active Filter Tags -->
        <div class="mt-4">
          <.active_filter_tags
            filters={@filters}
            radius_km={@radius_km}
            categories={@categories}
            active_date_range={@active_date_range}
            default_radius={50}
            sort_by={@filters.sort_by}
          />
        </div>

        <!-- Events Grid/List -->
        <div class="mt-6">
          <%= if @loading or @events_loading do %>
            <.loading_skeleton />
          <% else %>
            <%= if @events == [] do %>
              <.empty_state />
            <% else %>
              <.event_results
                events={@events}
                view_mode={@view_mode}
                language={@language}
                pagination={@pagination}
                show_city={false}
              />

              <!-- Pagination -->
              <div class="mt-8">
                <.pagination pagination={@pagination} />
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>

    <div id="language-cookie-hook" phx-hook="LanguageCookie"></div>
    """
  end

  # Component: Filter Panel with radius selector
  # Uses shared EventListing components for radius and category selection
  defp filter_panel(assigns) do
    ~H"""
    <form phx-change="filter" class="space-y-6">
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <!-- Search Radius - using shared component -->
        <.radius_selector
          radius_km={@radius_km}
          default_radius={50}
          name="filter[radius]"
          form_mode={true}
        />

        <!-- Sort By -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">
            <%= gettext("Sort By") %>
          </label>
          <select
            name="filter[sort_by]"
            class="w-full px-3 py-2 border border-gray-300 rounded-md"
          >
            <option value="starts_at" selected={@filters.sort_by == :starts_at}>
              <%= gettext("Date") %>
            </option>
            <option value="popularity" selected={@filters.sort_by == :popularity}>
              <%= gettext("Popularity") %>
            </option>
            <option value="title" selected={@filters.sort_by == :title}>
              <%= gettext("Title") %>
            </option>
          </select>
        </div>
      </div>

      <!-- Categories - using shared component -->
      <.category_checkboxes
        categories={@categories}
        selected_ids={@filters.categories}
        name="filter[categories][]"
        form_mode={true}
      />
    </form>
    """
  end

  # Private functions

  defp fetch_events(socket) do
    start_time = System.monotonic_time(:millisecond)
    city = socket.assigns.city
    filters = socket.assigns.filters
    language = socket.assigns.language
    aggregate = socket.assigns.aggregate

    # Get city coordinates
    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    # Build query filters with geographic filtering at database level
    query_filters =
      Map.merge(filters, %{
        language: language,
        sort_order: filters[:sort_order] || :asc,
        # Use filter's page_size, default to 30 (divisible by 3 for grid layout)
        page_size: filters[:page_size] || 30,
        page: filters[:page] || 1,
        # Add geographic filtering parameters
        center_lat: lat,
        center_lng: lng,
        radius_km: filters[:radius_km] || @default_radius_km
      })

    # Get events with geographic filtering done at database level
    # PERF: Uses consolidated query that returns events + counts in single pass
    # Previously this was 3 separate queries repeating the same geo filter
    {geographic_events, total_count, all_events_count, date_range_counts} =
      if lat && lng do
        # Build filters for "all events" count (without date restrictions)
        count_filters = Map.delete(query_filters, :page) |> Map.delete(:page_size)
        date_range_count_filters = EventFilters.build_date_range_count_filters(count_filters)

        # Use cached date range counts (15 min TTL) - cache key includes city slug and radius
        date_counts =
          CityPageCache.get_date_range_counts(
            city.slug,
            filters[:radius_km] || @default_radius_km,
            fn ->
              PublicEventsEnhanced.get_quick_date_range_counts(date_range_count_filters)
            end
          )

        # CONSOLIDATED QUERY: Get events, total count, and all_events count in single pass
        # This replaces 3 separate calls to list_events_with_aggregation + 2x count_events_with_aggregation
        {events, total, all_events} =
          PublicEventsEnhanced.list_events_with_aggregation_and_counts(
            query_filters
            |> Map.put(:aggregate, aggregate)
            |> Map.put(:ignore_city_in_aggregation, true)
            |> Map.put(:viewing_city, city)
            |> Map.put(
              :all_events_filters,
              date_range_count_filters
              |> Map.put(:aggregate, aggregate)
              |> Map.put(:ignore_city_in_aggregation, true)
              |> Map.put(:viewing_city, city)
            )
          )

        {events, total, all_events, date_counts}
      else
        # No coordinates, fallback to empty list
        {[], 0, 0, %{}}
      end

    # Use actual counts for pagination
    page = filters[:page] || 1
    page_size = filters[:page_size] || 30
    total_entries = total_count
    total_pages = ceil(total_entries / page_size)

    pagination = %Pagination{
      entries: geographic_events,
      page_number: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }

    # Log performance metrics
    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info(
      "[CityPage] fetch_events for #{city.slug} completed in #{duration}ms " <>
        "(events: #{length(geographic_events)}, total: #{total_entries}, " <>
        "radius: #{filters[:radius_km] || @default_radius_km}km)"
    )

    socket
    |> assign(:events, geographic_events)
    |> assign(:pagination, pagination)
    # Use the total from pagination, not current page length
    |> assign(:total_events, total_entries)
    # Count of all events (no date filter)
    |> assign(:all_events_count, all_events_count)
    |> assign(:date_range_counts, date_range_counts)
    |> assign(:loading, false)
  end

  defp fetch_nearby_cities(socket) do
    # No longer showing nearby cities
    socket
  end

  defp page_title(city) do
    "Events in #{city.name}, #{city.country.name} | Eventasaurus"
  end

  defp meta_description(city) do
    "Discover upcoming events in #{city.name}, #{city.country.name}. Find concerts, festivals, workshops, and more happening near you."
  end

  # Helper functions moved to SEOHelpers module

  defp parse_id_list(nil), do: []
  defp parse_id_list([]), do: []

  defp parse_id_list(ids) when is_list(ids) do
    ids
    |> Enum.map(fn id ->
      case id do
        id when is_integer(id) ->
          id

        id when is_binary(id) ->
          case Integer.parse(id) do
            {num, _} -> num
            _ -> nil
          end

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_id_list(ids) when is_binary(ids) do
    ids
    |> String.split(",")
    |> Enum.map(fn id ->
      case Integer.parse(id) do
        {num, _} -> num
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Commented out - price display temporarily hidden as no APIs provide price data
  # See GitHub issue #1281 for details
  # defp format_price_range(event) do
  #   cond do
  #     event.min_price && event.max_price && event.min_price == event.max_price ->
  #       "$#{event.min_price}"
  #
  #     event.min_price && event.max_price ->
  #       "$#{event.min_price} - $#{event.max_price}"
  #
  #     event.min_price ->
  #       "From $#{event.min_price}"
  #
  #     event.max_price ->
  #       "Up to $#{event.max_price}"
  #
  #     true ->
  #       "Price not available"
  #   end
  # end

  # Detect which quick date range (if any) matches the current filters
  defp detect_active_date_range(filters) do
    case {filters.start_date, filters.end_date} do
      {nil, nil} ->
        # No date filter = "All Events"
        nil

      {start_date, end_date} when not is_nil(start_date) and not is_nil(end_date) ->
        # Check if it matches any known quick date range
        Enum.find(
          [
            :today,
            :tomorrow,
            :this_weekend,
            :next_7_days,
            :next_30_days,
            :this_month,
            :next_month
          ],
          fn range ->
            {range_start, range_end} = PublicEventsEnhanced.calculate_date_range(range)
            dates_match?(start_date, range_start) and dates_match?(end_date, range_end)
          end
        )

      _ ->
        # Custom date range
        nil
    end
  end

  # Compare two DateTimes, ignoring time component differences
  defp dates_match?(dt1, dt2) when is_struct(dt1, DateTime) and is_struct(dt2, DateTime) do
    Date.compare(DateTime.to_date(dt1), DateTime.to_date(dt2)) == :eq
  end

  defp dates_match?(_, _), do: false

  # Apply URL params during deferred loading
  # This captures query string params (page, date filters, etc.) that weren't available in mount
  defp apply_url_params_for_deferred_load(socket, params) do
    page = parse_integer(params["page"]) || 1
    radius_km = parse_integer(params["radius"]) || socket.assigns.radius_km

    # Parse date params from URL
    start_date = parse_date(params["start_date"])
    end_date = parse_date(params["end_date"])

    # Determine if URL has explicit date state
    # Priority:
    # 1. date_filter=all means "All Events" (no date filter)
    # 2. start_date/end_date params mean specific date filter
    # 3. No date params = apply default 30-day filter
    {final_start_date, final_end_date} =
      cond do
        params["date_filter"] == "all" ->
          # Explicit "All Events" - no date filter
          {nil, nil}

        Map.has_key?(params, "start_date") or Map.has_key?(params, "end_date") ->
          # URL explicitly sets date range
          {start_date, end_date}

        true ->
          # No date params in URL - show all events (paginated)
          {nil, nil}
      end

    # Parse categories
    category_ids =
      case params do
        %{"category" => slug} when is_binary(slug) and slug != "" ->
          case Categories.get_category_by_slug(slug) do
            nil -> []
            category -> [category.id]
          end

        %{"categories" => ids} ->
          parse_id_list(ids)

        _ ->
          []
      end

    # Build filters from URL params
    filters = %{
      search: params["search"],
      categories: category_ids,
      start_date: final_start_date,
      end_date: final_end_date,
      radius_km: radius_km,
      sort_by: parse_sort(params["sort"]),
      sort_order: :asc,
      page: page,
      page_size: 30,
      show_past: parse_boolean(params["show_past"])
    }

    # Detect active date range for UI highlighting
    active_date_range = detect_active_date_range(filters)

    socket
    |> assign(:filters, filters)
    |> assign(:radius_km, radius_km)
    |> assign(:active_date_range, active_date_range)
    |> assign(:pagination, %Pagination{
      entries: [],
      page_number: page,
      page_size: 30,
      total_entries: 0,
      total_pages: 0
    })
  end

  defp apply_params_to_filters(socket, params) do
    # Handle both singular category (slug from breadcrumb) and plural categories (IDs from filter UI)
    category_ids =
      case params do
        %{"category" => slug} when is_binary(slug) and slug != "" ->
          # Single category slug from breadcrumb like /c/krakow?category=film
          case Categories.get_category_by_slug(slug) do
            nil -> []
            category -> [category.id]
          end

        %{"categories" => ids} ->
          # Multiple category IDs from query params
          parse_id_list(ids)

        _ ->
          []
      end

    # Handle date filter - check for explicit "all" marker first
    {start_date, end_date} =
      if params["date_filter"] == "all" do
        # Explicit "All Events" - no date filter
        {nil, nil}
      else
        {parse_date(params["start_date"]), parse_date(params["end_date"])}
      end

    filters = %{
      search: params["search"],
      categories: category_ids,
      start_date: start_date,
      end_date: end_date,
      radius_km: parse_integer(params["radius"]) || socket.assigns.radius_km,
      sort_by: parse_sort(params["sort"]),
      sort_order: :asc,
      page: parse_integer(params["page"]) || 1,
      page_size: 30,
      show_past: parse_boolean(params["show_past"])
    }

    # Update active_date_range for UI highlighting
    active_date_range = detect_active_date_range(filters)

    socket
    |> assign(:filters, filters)
    |> assign(:radius_km, filters.radius_km)
    |> assign(:active_date_range, active_date_range)
  end

  defp build_path(socket, filters) do
    params = build_filter_params(filters)
    ~p"/c/#{socket.assigns.city.slug}?#{params}"
  end

  defp build_filter_params(filters) do
    # Start with the base filter params
    base_params =
      filters
      |> Map.take([
        :search,
        :categories,
        :start_date,
        :end_date,
        :radius_km,
        :sort_by,
        :page,
        :show_past
      ])
      |> Enum.reject(fn
        {_k, nil} -> true
        {_k, ""} -> true
        # Empty categories list
        {_k, []} -> true
        {:page, 1} -> true
        # Don't include default radius
        {:radius_km, @default_radius_km} -> true
        {:sort_by, :starts_at} -> true
        # Don't include default
        {:show_past, false} -> true
        _ -> false
      end)
      |> Enum.map(fn
        {:categories, cats} when is_list(cats) -> {"categories", Enum.join(cats, ",")}
        {:start_date, date} -> {"start_date", DateTime.to_iso8601(date)}
        {:end_date, date} -> {"end_date", DateTime.to_iso8601(date)}
        {:radius_km, radius} -> {"radius", to_string(radius)}
        {:sort_by, sort} -> {"sort", to_string(sort)}
        {:page, page} -> {"page", to_string(page)}
        {:show_past, val} -> {"show_past", to_string(val)}
        {k, v} -> {to_string(k), to_string(v)}
      end)
      |> Enum.into(%{})

    # If there's no date filter (All Events), add explicit marker
    # This ensures pagination preserves the "all events" state
    if is_nil(filters[:start_date]) and is_nil(filters[:end_date]) do
      Map.put(base_params, "date_filter", "all")
    else
      base_params
    end
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_sort(nil), do: :starts_at
  defp parse_sort("title"), do: :title
  defp parse_sort("popularity"), do: :popularity
  # Distance removed - unclear UX ("distance from what?")
  defp parse_sort("distance"), do: :starts_at
  defp parse_sort(_), do: :starts_at

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    # Try parsing as full datetime first (preserves time component)
    case DateTime.from_iso8601(date_str) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        # Fallback to date-only parsing (defaults to midnight)
        case Date.from_iso8601(date_str) do
          {:ok, date} -> DateTime.new!(date, ~T[00:00:00])
          _ -> nil
        end
    end
  end

  defp parse_boolean(nil), do: false
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean(_), do: false

  # Fetch aggregated statistics for city JSON-LD
  defp fetch_city_stats(city) do
    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    if lat && lng do
      # Count total upcoming events in the city (within default radius)
      {_start_date, _end_date} = PublicEventsEnhanced.calculate_date_range(:next_30_days)

      events_count =
        PublicEventsEnhanced.count_events(%{
          center_lat: lat,
          center_lng: lng,
          radius_km: @default_radius_km,
          show_past: false
        })

      # Count venues in the city
      venues_count =
        EventasaurusApp.Repo.aggregate(
          from(v in EventasaurusApp.Venues.Venue, where: v.city_id == ^city.id),
          :count
        )

      # Count distinct categories from events in the city
      # This is more complex - we need to query events and get their categories
      # For now, we'll use a simpler approach and just count all available categories
      # TODO: In the future, we could count only categories that have events in this city
      categories_count = length(Categories.list_categories())

      %{
        events_count: events_count,
        venues_count: venues_count,
        categories_count: categories_count
      }
    else
      # No coordinates, return zeros
      %{
        events_count: 0,
        venues_count: 0,
        categories_count: 0
      }
    end
  end

  # Build Open Graph meta tags for city pages
  defp build_city_open_graph(city, _stats, social_card_path, request_uri) do
    # Build absolute URLs using UrlHelper for consistency
    # Note: Social cards are server-generated PNGs, not CDN-hosted assets
    image_url = EventasaurusWeb.UrlHelper.build_url(social_card_path, request_uri)
    canonical_url = EventasaurusWeb.UrlHelper.build_url("/c/#{city.slug}", request_uri)

    # Build description with stats
    description = meta_description(city)

    # Generate Open Graph tags
    Phoenix.HTML.Safe.to_iodata(
      OpenGraphComponent.open_graph_tags(%{
        type: "website",
        title: page_title(city),
        description: description,
        image_url: image_url,
        image_width: 800,
        image_height: 419,
        url: canonical_url,
        site_name: "Wombie",
        locale: "en_US",
        twitter_card: "summary_large_image"
      })
    )
    |> IO.iodata_to_binary()
  end
end
