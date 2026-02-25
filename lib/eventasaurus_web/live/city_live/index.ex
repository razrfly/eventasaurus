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
  alias EventasaurusWeb.Live.Helpers.CityPageFilters
  alias EventasaurusWeb.Helpers.LanguageDiscovery
  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.JsonLd.CitySchema
  alias Eventasaurus.SocialCards.UrlBuilder
  alias EventasaurusWeb.Cache.CityPageCache
  alias EventasaurusWeb.Telemetry.CityPageTelemetry

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.Components.EventListing

  on_mount {EventasaurusWeb.Live.LanguageHooks, :attach_language_handler}

  @default_radius_km 50

  # Debug mode: bypass cache and show data source comparison
  # Enable with ?debug=true query param (dev environment only)
  @debug_enabled Mix.env() == :dev

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
          #
          # SEO FIX (Issue #3146): Generate SEO metadata SYNCHRONOUSLY in mount
          # Social media crawlers don't execute JavaScript, so they only see the
          # initial HTML. We must set OG tags before the first render.
          # City stats queries are fast (COUNT queries), so we run them here.
          # Event loading remains deferred for performance.

          # Generate city stats and SEO metadata synchronously (cached COUNT queries)
          # Phase 3 optimization (Issue #3331): Cache city stats to avoid repeated COUNT queries
          city_stats =
            CityPageCache.get_city_stats(city.slug, @default_radius_km, fn ->
              fetch_city_stats_uncached(city)
            end)

          json_ld = CitySchema.generate(city, city_stats)
          city_with_stats = Map.put(city, :stats, city_stats)
          social_card_path = UrlBuilder.build_path(:city, city_with_stats)
          og_tags = build_city_open_graph(city, city_stats, social_card_path, request_uri)

          # TELEMETRY: Start page load timing
          timing_ctx = CityPageTelemetry.start_timing(city_slug)

          {:ok,
           socket
           |> assign(:city, city)
           |> assign(:city_slug, city_slug)
           |> assign(:language, language)
           |> assign(:request_uri, request_uri)
           |> assign(:timing_ctx, timing_ctx)
           # Initialize with empty/loading states - will be populated by handle_info
           |> assign(:available_languages, ["en"])
           |> assign(:radius_km, @default_radius_km)
           |> assign(:view_mode, "grid")
           |> assign(:filters, %{page: 1, page_size: 30})
           |> assign(:show_filters, false)
           |> assign(:loading, true)
           |> assign(:events_loading, true)
           # Debug mode for comparing data sources (dev only)
           |> assign(:debug_mode, false)
           |> assign(:debug_data, nil)
           # Cache status pill visibility (compile-time dev check, Issue #3675)
           |> assign(:debug_enabled, @debug_enabled)
           # Cache status for dev debug pill (Issue #3675)
           |> assign(:cache_status, nil)
           |> assign(:total_events, 0)
           |> assign(:all_events_count, 0)
           |> assign(:categories, [])
           |> assign(:events, [])
           # SEO metadata - set synchronously for crawlers (Issue #3146)
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

    # STAGE 1: Load lightweight data (categories, languages)
    city_slug = socket.assigns.city_slug

    # Get dynamically available languages for this city (cached)
    # Phase 3 optimization (Issue #3331): Cache available languages per city
    available_languages =
      CityPageCache.get_available_languages(city_slug, fn ->
        try do
          LanguageDiscovery.get_available_languages_for_city(city_slug)
        rescue
          e ->
            Logger.warning(
              "Language discovery failed for city_slug=#{city_slug}: #{Exception.message(e)}"
            )

            ["en"]
        end
      end)

    # Get categories (cached)
    categories = CityPageCache.get_categories(&Categories.list_categories/0)

    # NOTE: SEO metadata (open_graph, meta tags, json_ld) is set synchronously in mount
    # so crawlers see it in the initial HTML response (Issue #3146)

    # TELEMETRY: Mark initial data loaded
    timing_ctx =
      socket.assigns[:timing_ctx]
      |> CityPageTelemetry.mark(:initial_data_loaded)

    socket =
      socket
      |> assign(:available_languages, available_languages)
      |> assign(:categories, categories)
      |> assign(:loading, false)
      |> assign(:timing_ctx, timing_ctx)

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
          socket =
            socket
            |> fetch_events()
            |> fetch_nearby_cities()
            |> assign(:events_loading, false)
            # Clear deferred_loading flag - initial loading is complete
            |> assign(:deferred_loading, false)
            |> assign(:fetch_in_progress, false)

          # DEBUG MODE: Fetch comparison data if enabled
          socket =
            if socket.assigns[:debug_mode] do
              Logger.info("[DEBUG_MODE] Fetching comparison data for #{socket.assigns.city.slug}")
              debug_data = fetch_debug_comparison(socket)
              Logger.info("[DEBUG_MODE] Comparison data: #{inspect(Map.keys(debug_data))}")
              assign(socket, :debug_data, debug_data)
            else
              socket
            end

          # TELEMETRY: Complete page load timing
          if timing_ctx = socket.assigns[:timing_ctx] do
            timing_ctx
            |> CityPageTelemetry.mark(:events_loaded)
            |> CityPageTelemetry.finish_timing()
          end

          socket
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

  # Toggle debug comparison panel (dev only, Issue #3675)
  @impl true
  def handle_event("toggle_debug", _params, socket) do
    if @debug_enabled do
      if socket.assigns.debug_mode do
        # Turning off — just hide the panel
        {:noreply, assign(socket, :debug_mode, false)}
      else
        # Turning on — fetch comparison data then show
        debug_data = fetch_debug_comparison(socket)
        {:noreply, socket |> assign(:debug_mode, true) |> assign(:debug_data, debug_data)}
      end
    else
      {:noreply, socket}
    end
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
      <!-- DEBUG PANEL: Data source comparison (dev only, ?debug=true) -->
      <%= if @debug_mode and @debug_data do %>
        <.debug_panel debug_data={@debug_data} />
      <% end %>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header with Title and Controls -->
        <div class="flex items-center justify-between mb-6">
          <div class="flex items-center gap-3">
            <h1 class="text-3xl font-bold text-gray-900">
              <%= gettext("Events in %{city}", city: @city.name) %>
            </h1>
            <%= if @debug_enabled and @cache_status do %>
              <.cache_status_pill status={@cache_status} debug_mode={@debug_mode} />
            <% end %>
          </div>
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

  # Component: Cache status pill (dev only, Issue #3675)
  # Shows which query path served the page as a colored pill next to the city title.
  # Clickable to toggle the full debug comparison panel.
  # Only rendered when @debug_enabled is true (compile-time dev check).
  defp cache_status_pill(assigns) do
    ~H"""
    <button
      phx-click="toggle_debug"
      class={"flex items-center gap-1.5 text-xs font-mono px-2 py-0.5 rounded-full cursor-pointer hover:opacity-80 transition-opacity " <> if(@debug_mode, do: "bg-yellow-100 text-yellow-800 ring-1 ring-yellow-400", else: "bg-gray-100 text-gray-600")}
    >
      <span class={"w-2 h-2 rounded-full " <> status_color(@status)}></span>
      <%= status_label(@status) %>
    </button>
    """
  end

  defp status_color(:live_query), do: "bg-blue-500"
  defp status_color(:base_hit), do: "bg-green-500"
  defp status_color(:hit), do: "bg-green-500"
  defp status_color(:miss), do: "bg-orange-500"
  defp status_color(:fallback), do: "bg-purple-500"
  defp status_color(:stale_empty), do: "bg-orange-500"
  defp status_color(:no_coords), do: "bg-red-500"
  defp status_color(_), do: "bg-gray-400"

  defp status_label(:live_query), do: "LIVE QUERY"
  defp status_label(:base_hit), do: "BASE HIT"
  defp status_label(:hit), do: "HIT"
  defp status_label(:miss), do: "MISS"
  defp status_label(:fallback), do: "FALLBACK"
  defp status_label(:stale_empty), do: "STALE-EMPTY"
  defp status_label(:no_coords), do: "NO COORDS"
  defp status_label(status), do: to_string(status) |> String.upcase()

  # Component: Debug Panel showing data source comparison
  # Only shown in dev when ?debug=true
  defp debug_panel(assigns) do
    ~H"""
    <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4 mb-4">
      <div class="flex items-center mb-2">
        <Heroicons.bug_ant class="w-6 h-6 text-yellow-600 mr-2" />
        <h2 class="text-lg font-bold text-yellow-800">Debug Mode: Data Source Comparison</h2>
      </div>
      <p class="text-sm text-yellow-700 mb-4">
        Comparing event counts from different data sources for city: <strong><%= @debug_data.city_slug %></strong>
        (radius: <%= @debug_data.radius_km %>km) at <%= Calendar.strftime(@debug_data.fetched_at, "%H:%M:%S") %>
      </p>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <!-- Direct Query -->
        <div class="bg-white p-4 rounded-lg shadow">
          <h3 class="font-semibold text-gray-800 mb-2">1. Direct Query</h3>
          <p class="text-xs text-gray-500 mb-2">PublicEventsEnhanced (bypasses cache)</p>
          <%= case @debug_data.direct_query.status do %>
            <% :ok -> %>
              <p class="text-2xl font-bold text-blue-600"><%= @debug_data.direct_query.event_count %> events</p>
              <p class="text-sm text-gray-600">Total: <%= @debug_data.direct_query.total_count %></p>
              <p class="text-xs text-gray-500"><%= @debug_data.direct_query.duration_ms %>ms</p>
            <% :error -> %>
              <p class="text-red-600">Error: <%= @debug_data.direct_query.error %></p>
          <% end %>
        </div>

        <!-- Cachex Base Cache -->
        <div class="bg-white p-4 rounded-lg shadow">
          <h3 class="font-semibold text-gray-800 mb-2">2. Cachex Base Cache</h3>
          <p class="text-xs text-gray-500 mb-2">CityPageCache.get_base_events</p>
          <%= case @debug_data.cachex_base.status do %>
            <% :hit -> %>
              <p class="text-2xl font-bold text-green-600"><%= @debug_data.cachex_base.event_count %> events</p>
              <p class="text-sm text-gray-600">All events: <%= @debug_data.cachex_base.all_events_count %></p>
              <p class="text-xs text-gray-500">
                Cached: <%= if @debug_data.cachex_base.cached_at, do: Calendar.strftime(@debug_data.cachex_base.cached_at, "%H:%M:%S"), else: "?" %>
              </p>
            <% :miss -> %>
              <p class="text-2xl font-bold text-orange-600">MISS</p>
              <p class="text-sm text-gray-600">Cache not populated</p>
            <% :error -> %>
              <p class="text-red-600">Error: <%= @debug_data.cachex_base.error %></p>
          <% end %>
        </div>

        <!-- Current Path -->
        <div class="bg-white p-4 rounded-lg shadow">
          <h3 class="font-semibold text-gray-800 mb-2">3. Current Path</h3>
          <p class="text-xs text-gray-500 mb-2"><%= @debug_data.current_path.path %></p>
          <%= if @debug_data.current_path[:event_count] do %>
            <p class="text-2xl font-bold text-indigo-600"><%= @debug_data.current_path.event_count %> events</p>
            <p class="text-sm text-gray-600">Total: <%= @debug_data.current_path.total_count %></p>
            <p class="text-xs text-gray-500">All: <%= @debug_data.current_path.all_events_count %></p>
          <% else %>
            <p class="text-sm text-gray-600"><%= @debug_data.current_path[:note] || @debug_data.current_path[:error] %></p>
          <% end %>
        </div>
      </div>

      <!-- Sample Events Comparison -->
      <details class="mt-4">
        <summary class="cursor-pointer text-sm font-medium text-yellow-800">Show Sample Events</summary>
        <div class="mt-2 grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <div>
            <h4 class="font-semibold">Direct Query:</h4>
            <%= if @debug_data.direct_query[:sample_events] do %>
              <ul class="list-disc pl-4">
                <%= for event <- @debug_data.direct_query.sample_events do %>
                  <li>
                    <%= event.title %>
                    <%= if event.has_image, do: "📷", else: "❌" %>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
          <div>
            <h4 class="font-semibold">Cachex:</h4>
            <%= if @debug_data.cachex_base[:sample_events] do %>
              <ul class="list-disc pl-4">
                <%= for event <- @debug_data.cachex_base.sample_events do %>
                  <li>
                    <%= event.title %>
                    <%= if event.has_image, do: "📷", else: "❌" %>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
      </details>
    </div>
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

    # Use city_id for exact city-boundary filtering instead of radius (Issue #3673)
    radius_km = @default_radius_km

    # Get events with geographic filtering - uses cache to prevent OOM (Issue #3347)
    {geographic_events, total_count, all_events_count, date_range_counts, cache_status} =
      if city.id do
        # Build filters using city_id for consistent results across all paths
        query_filters =
          Map.merge(filters, %{
            language: language,
            sort_order: filters[:sort_order] || :asc,
            page_size: filters[:page_size] || 30,
            page: filters[:page] || 1,
            city_id: city.id
          })

        count_filters = Map.delete(query_filters, :page) |> Map.delete(:page_size)
        date_range_count_filters = EventFilters.build_date_range_count_filters(count_filters)

        if caching_enabled?() do
          # Production path: use cache chain with MV fallback
          # Issue #3363: Use base cache for date-only filters (instant response)
          # Fall back to per-filter cache for category/search filters
          if CityPageFilters.can_use_base_cache?(filters) do
            # Date-only filters can use base cache with in-memory filtering
            case CityPageCache.get_base_events(city.slug, radius_km) do
              {:ok, base_data} when base_data.events != [] ->
                # Base cache hit with data - filter in-memory for instant response
                page_opts = [page: filters[:page] || 1, page_size: filters[:page_size] || 30]
                result = CityPageFilters.filter_base_events(base_data, filters, page_opts)

                # Calculate date counts from base cache (more efficient, same data source)
                date_counts = CityPageFilters.calculate_date_range_counts(base_data)

                Logger.info(
                  "[CityPage] BASE Cache HIT for #{city.slug} " <>
                    "(filtered #{result.total_count} from #{length(base_data.events)} events)"
                )

                {result.events, result.total_count, result.all_events_count, date_counts, :base_hit}

              {:ok, %{events: []} = _empty_cache} ->
                # Issue #3490: Cache hit but EMPTY - verify with live query before returning empty
                # This catches stale caches that were populated when no events existed
                Logger.warning(
                  "[CityPage] BASE Cache STALE-EMPTY for #{city.slug} - running live query"
                )

                fetch_live_query(city, query_filters, date_range_count_filters)

              {:miss, nil} ->
                # No base cache yet - fall back to per-filter cache
                Logger.info(
                  "[CityPage] BASE Cache MISS for #{city.slug} - falling back to per-filter cache"
                )

                fetch_from_filter_cache(
                  city,
                  radius_km,
                  filters,
                  aggregate,
                  query_filters,
                  date_range_count_filters
                )
            end
          else
            # Categories or search active - must use per-filter cache
            fetch_from_filter_cache(city, radius_km, filters, aggregate, query_filters, date_range_count_filters)
          end
        else
          # Caching OFF: run live query directly (Issue #3673)
          # Uses the same code path as the mobile slow path for consistent counts
          fetch_live_query(city, query_filters, date_range_count_filters)
        end
      else
        # No city, fallback to empty list
        {[], 0, 0, %{}, :no_coords}
      end

    # Filter out events with nil slugs to prevent rendering crashes
    # This can happen when events are scraped without proper slug generation
    geographic_events =
      Enum.filter(geographic_events, fn
        # PublicEvent with nil slug - exclude
        %EventasaurusDiscovery.PublicEvents.PublicEvent{slug: nil} ->
          Logger.warning("[CityPage] Filtering out event with nil slug")
          false

        # All other events/aggregations - include
        _ ->
          true
      end)

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
        "radius: #{radius_km}km, cache: #{cache_status})"
    )

    socket =
      socket
      |> assign(:events, geographic_events)
      |> assign(:pagination, pagination)
      |> assign(:total_events, total_entries)
      |> assign(:all_events_count, all_events_count)
      |> assign(:date_range_counts, date_range_counts)
      |> assign(:cache_status, cache_status)
      |> assign(:loading, false)

    socket
  end

  # Fetch events from per-filter cache (used for category/search filters or base cache miss)
  defp fetch_from_filter_cache(city, radius_km, filters, aggregate, query_filters, date_range_count_filters) do
    # Build cache options from current filters
    cache_opts = build_cache_opts(filters, aggregate)

    # Try to get events from per-filter cache (stale-while-revalidate pattern)
    case CityPageCache.get_aggregated_events(city.slug, radius_km, cache_opts) do
      {:ok, cached} when cached.events != [] ->
        # Issue #3373: Use base cache for date counts to ensure consistency
        # If base cache is not available, fall back to separate date counts cache
        date_counts = get_date_counts_consistently(city.slug, radius_km, date_range_count_filters)

        Logger.info(
          "[CityPage] Filter Cache HIT for #{city.slug} (cached_at: #{cached.cached_at})"
        )

        {cached.events, cached.total_count, cached.all_events_count, date_counts, :hit}

      {:ok, %{events: []} = _empty_cache} ->
        # Issue #3675: Cache hit but EMPTY - run live query instead of MV fallback
        # Live query produces correct aggregation (movies + source groups + containers)
        Logger.warning(
          "[CityPage] Filter Cache STALE-EMPTY for #{city.slug} - running live query"
        )

        fetch_live_query(city, query_filters, date_range_count_filters)

      {:miss, nil} ->
        # Issue #3675: Cache miss - run live query instead of MV fallback
        # Live query is slower (~200-500ms) but produces correct results
        Logger.info(
          "[CityPage] Filter Cache MISS for #{city.slug} - running live query"
        )

        fetch_live_query(city, query_filters, date_range_count_filters)
    end
  end

  # Get date counts from a consistent data source
  # Priority: 1. Base cache (same data source as events)
  #           2. Live query via date counts cache
  defp get_date_counts_consistently(city_slug, radius_km, date_range_count_filters) do
    # Try base cache first (same data source as base cache path)
    case CityPageCache.get_base_events(city_slug, radius_km) do
      {:ok, base_data} when base_data.events != [] ->
        CityPageFilters.calculate_date_range_counts(base_data)

      _ ->
        # Base cache miss or empty — fall back to live query
        CityPageCache.get_date_range_counts(
          city_slug,
          radius_km,
          fn ->
            PublicEventsEnhanced.get_quick_date_range_counts(date_range_count_filters)
          end
        )
    end
  end

  # Direct live query path — used when caching is OFF (Issue #3673)
  # Runs the same aggregation pipeline as the mobile slow path for consistent counts
  defp fetch_live_query(city, query_filters, date_range_count_filters) do
    live_opts =
      query_filters
      |> Map.put(:aggregate, true)
      |> Map.put(:ignore_city_in_aggregation, true)
      |> Map.put(:viewing_city, city)
      |> EventFilters.enrich_with_all_events_filters()

    {events, total_count, all_events_count} =
      PublicEventsEnhanced.list_events_with_aggregation_and_counts(live_opts)

    date_counts = PublicEventsEnhanced.get_quick_date_range_counts(date_range_count_filters)

    Logger.info(
      "[CityPage] LIVE QUERY for #{city.slug} " <>
        "(events: #{length(events)}, total: #{total_count}, all: #{all_events_count})"
    )

    {events, total_count, all_events_count, date_counts, :live_query}
  end

  defp caching_enabled? do
    Application.get_env(:eventasaurus, :enable_caching, true)
  end


  # Build cache options from filter state
  defp build_cache_opts(filters, aggregate) do
    opts = []

    # Only include non-default values to maximize cache hits
    opts =
      if filters[:page] && filters[:page] != 1,
        do: Keyword.put(opts, :page, filters[:page]),
        else: opts

    opts =
      if filters[:page_size] && filters[:page_size] != 30,
        do: Keyword.put(opts, :page_size, filters[:page_size]),
        else: opts

    opts =
      if filters[:categories] && filters[:categories] != [],
        do: Keyword.put(opts, :categories, filters[:categories]),
        else: opts

    # Include date filter parameters (Issue #3357)
    # These determine which events are shown, so must be part of cache key
    opts =
      if filters[:start_date],
        do: Keyword.put(opts, :start_date, DateTime.to_iso8601(filters[:start_date])),
        else: opts

    opts =
      if filters[:end_date],
        do: Keyword.put(opts, :end_date, DateTime.to_iso8601(filters[:end_date])),
        else: opts

    opts =
      if filters[:show_past] == true,
        do: Keyword.put(opts, :show_past, true),
        else: opts

    # Convert sort_by to string for cache key consistency (Issue #3357)
    # Job args store sort_by as string due to JSON serialization
    opts =
      if filters[:sort_by],
        do: Keyword.put(opts, :sort_by, to_string(filters[:sort_by])),
        else: opts

    opts =
      if aggregate != true,
        do: Keyword.put(opts, :aggregate, aggregate),
        else: opts

    normalized_search =
      filters[:search] |> to_string() |> String.trim()

    opts =
      if normalized_search != "",
        do: Keyword.put(opts, :search, normalized_search),
        else: opts

    opts
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

    # Debug mode: ?debug=true enables data source comparison (dev only)
    debug_mode = @debug_enabled and parse_boolean(params["debug"])

    if debug_mode do
      Logger.info("[DEBUG_MODE] Enabled for city page - will fetch comparison data")
    end

    # Parse date params from URL
    start_date = parse_date(params["start_date"])
    end_date = parse_date(params["end_date"])

    # Determine if URL has explicit date state
    # Priority:
    # 1. date_filter=all means "All Events" (no date filter)
    # 2. date_filter=today/tomorrow/etc means quick date range
    # 3. start_date/end_date params mean specific date filter
    # 4. No date params = show all events (paginated)
    {final_start_date, final_end_date, show_past} =
      cond do
        params["date_filter"] == "all" ->
          # Explicit "All Events" - no date filter
          {nil, nil, false}

        EventFilters.quick_date_range?(params["date_filter"]) ->
          # Quick date filter from URL (today, tomorrow, this_weekend, etc.)
          range_atom = String.to_existing_atom(params["date_filter"])
          {start_dt, end_dt} = EventFilters.get_quick_date_bounds(range_atom)
          {start_dt, end_dt, true}

        Map.has_key?(params, "start_date") or Map.has_key?(params, "end_date") ->
          # URL explicitly sets date range
          {start_date, end_date, true}

        true ->
          # No date params in URL - show all events (paginated)
          {nil, nil, false}
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
    # For show_past: use explicit param if present, otherwise use calculated value from date filter
    final_show_past =
      if Map.has_key?(params, "show_past") do
        parse_boolean(params["show_past"])
      else
        show_past
      end

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
      show_past: final_show_past
    }

    # Detect active date range for UI highlighting
    active_date_range = detect_active_date_range(filters)

    socket
    |> assign(:filters, filters)
    |> assign(:radius_km, radius_km)
    |> assign(:active_date_range, active_date_range)
    |> assign(:debug_mode, debug_mode)
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

    # Handle date filter - translate date_filter param to actual date bounds
    # Priority:
    # 1. date_filter=all → no date filter (show all)
    # 2. date_filter=today/tomorrow/etc → quick date range
    # 3. start_date/end_date params → custom date range
    {start_date, end_date, date_filter_show_past} =
      cond do
        params["date_filter"] == "all" ->
          # Explicit "All Events" - no date filter
          {nil, nil, false}

        EventFilters.quick_date_range?(params["date_filter"]) ->
          # Quick date filter (today, tomorrow, this_weekend, etc.)
          range_atom = String.to_existing_atom(params["date_filter"])
          {start_dt, end_dt} = EventFilters.get_quick_date_bounds(range_atom)
          {start_dt, end_dt, true}

        true ->
          # Custom date range or no date params
          {parse_date(params["start_date"]), parse_date(params["end_date"]), false}
      end

    # For show_past: use explicit param if present, otherwise derive from date filter
    final_show_past =
      if Map.has_key?(params, "show_past") do
        parse_boolean(params["show_past"])
      else
        date_filter_show_past
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
      show_past: final_show_past
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

  # Fetch aggregated statistics for city JSON-LD (uncached version)
  # Called by CityPageCache.get_city_stats when cache misses
  defp fetch_city_stats_uncached(city) do
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

  # ============================================================================
  # DEBUG MODE: Compare data sources for Issue #3376 investigation
  # Enable with ?debug=true query param (dev environment only)
  # ============================================================================

  # Fetch data from all three sources for comparison
  defp fetch_debug_comparison(socket) do
    city = socket.assigns.city
    radius_km = socket.assigns.filters[:radius_km] || @default_radius_km
    language = socket.assigns.language
    filters = socket.assigns.filters

    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    debug_data = %{
      fetched_at: DateTime.utc_now(),
      city_slug: city.slug,
      radius_km: radius_km
    }

    # 1. Direct database query (bypasses all caching)
    direct_result =
      try do
        start_time = System.monotonic_time(:millisecond)

        query_filters = %{
          language: language,
          sort_by: :starts_at,
          sort_order: :asc,
          page_size: 1000,
          page: 1,
          center_lat: lat,
          center_lng: lng,
          radius_km: radius_km,
          show_past: false
        }

        # Use PublicEventsEnhanced directly to bypass cache
        # Returns tuple: {events, total_count, all_events_count}
        {events, total_count, all_events_count} =
          PublicEventsEnhanced.list_events_with_aggregation_and_counts(query_filters)

        duration = System.monotonic_time(:millisecond) - start_time

        %{
          status: :ok,
          event_count: length(events),
          total_count: total_count,
          all_events_count: all_events_count,
          duration_ms: duration,
          sample_events: Enum.take(events, 3) |> Enum.map(&event_summary/1)
        }
      rescue
        e ->
          %{status: :error, error: Exception.message(e)}
      end

    # 2. Cachex base cache
    cache_result =
      try do
        start_time = System.monotonic_time(:millisecond)

        case CityPageCache.get_base_events(city.slug, radius_km) do
          {:ok, cached} ->
            duration = System.monotonic_time(:millisecond) - start_time

            %{
              status: :hit,
              event_count: length(cached.events),
              all_events_count: cached.all_events_count,
              cached_at: cached.cached_at,
              duration_ms: duration,
              sample_events: Enum.take(cached.events, 3) |> Enum.map(&event_summary/1)
            }

          {:miss, nil} ->
            %{status: :miss, event_count: 0}
        end
      rescue
        e ->
          %{status: :error, error: Exception.message(e)}
      end

    # 3. Current filter path (what the user is actually seeing)
    current_result =
      try do
        page_opts = [page: filters[:page] || 1, page_size: filters[:page_size] || 30]

        # Determine which path we're using
        if CityPageFilters.can_use_base_cache?(filters) do
          case CityPageCache.get_base_events(city.slug, radius_km) do
            {:ok, base_data} ->
              result = CityPageFilters.filter_base_events(base_data, filters, page_opts)

              %{
                path: "base_cache + in_memory_filter",
                event_count: length(result.events),
                total_count: result.total_count,
                all_events_count: result.all_events_count
              }

            {:miss, nil} ->
              %{path: "cache_miss", note: "base cache not populated"}
          end
        else
          %{path: "per_filter_cache (category/search active)", note: "skipped in debug"}
        end
      rescue
        e ->
          %{path: "error", error: Exception.message(e)}
      end

    debug_data
    |> Map.put(:direct_query, direct_result)
    |> Map.put(:cachex_base, cache_result)
    |> Map.put(:mv_fallback, %{status: :removed})
    |> Map.put(:current_path, current_result)
  end

  # Create a summary of an event for debug display
  defp event_summary(event) do
    %{
      id: Map.get(event, :id) || Map.get(event, :event_id),
      title: truncate(Map.get(event, :title) || Map.get(event, :display_title), 40),
      has_image: has_cover_image?(event)
    }
  end

  defp has_cover_image?(event) do
    url = Map.get(event, :cover_image_url)
    is_binary(url) and String.trim(url) != ""
  end

  defp truncate(nil, _), do: nil
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max - 3) <> "..."
end
