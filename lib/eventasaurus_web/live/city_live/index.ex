defmodule EventasaurusWeb.CityLive.Index do
  @moduledoc """
  LiveView for city-based event discovery pages.

  Displays events within a configurable radius of a city's center,
  using the city's dynamically calculated coordinates.
  """

  use EventasaurusWeb, :live_view
  require Logger

  import Ecto.Query, only: [from: 2]

  alias Eventasaurus.CDN
  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup
  alias EventasaurusWeb.Components.OpenGraphComponent
  alias EventasaurusWeb.Live.Helpers.EventFilters
  alias EventasaurusWeb.Helpers.LanguageDiscovery
  alias EventasaurusWeb.Helpers.LanguageHelpers
  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.JsonLd.CitySchema
  alias Eventasaurus.SocialCards.UrlBuilder
  alias EventasaurusWeb.Cache.CityPageCache

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.Components.EventCards

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
          # Get language from session or default to English
          language = get_connect_params(socket)["locale"] || socket.assigns[:language] || "en"

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
           |> assign(:filters, default_filters())
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
    # DEBUG: Artificial delay to visualize staged loading (remove in production)
    if Application.get_env(:eventasaurus, :debug_staged_loading, false) do
      Process.sleep(2000)
    end

    # STAGE 2: Load events (expensive geographic query)
    socket =
      try do
        socket
        |> fetch_events()
        |> fetch_nearby_cities()
        |> assign(:events_loading, false)
      rescue
        e ->
          Logger.error(
            "Failed to load events for city #{socket.assigns.city.slug}: #{inspect(e)}"
          )

          socket
          |> assign(:events, [])
          |> assign(:events_loading, false)
          |> assign(:total_events, 0)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_filtered_events, socket) do
    # DEBUG: Artificial delay to visualize staged loading on filter changes
    if Application.get_env(:eventasaurus, :debug_staged_loading, false) do
      Process.sleep(2000)
    end

    # Load events with current filters (expensive geographic query)
    socket =
      try do
        socket
        |> fetch_events()
        |> assign(:events_loading, false)
      rescue
        e ->
          Logger.error(
            "Failed to load filtered events for city #{socket.assigns.city.slug}: #{inspect(e)}"
          )

          socket
          |> assign(:events, [])
          |> assign(:events_loading, false)
          |> assign(:total_events, 0)
      end

    {:noreply, socket}
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
  def handle_event("change_language", %{"language" => language}, socket) do
    # ASYNC: Show skeleton immediately, load events in background
    socket =
      socket
      |> assign(:language, language)
      |> assign(:events_loading, true)

    send(self(), :load_filtered_events)
    {:noreply, socket}
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
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <div class="bg-white shadow-sm border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex justify-between items-center">
            <h1 class="text-3xl font-bold text-gray-900">
              <%= gettext("Events in %{city}", city: @city.name) %>
            </h1>
            <div class="flex items-center space-x-4">
              <!-- Language Switcher - Dynamic based on city -->
              <div class="flex bg-gray-100 rounded-lg p-1">
                <%= for lang <- @available_languages do %>
                  <button
                    phx-click="change_language"
                    phx-value-language={lang}
                    class={"px-3 py-1.5 rounded text-sm font-medium transition-colors #{if @language == lang, do: "bg-white shadow-sm text-blue-600", else: "text-gray-600 hover:text-gray-900"}"}
                    title={LanguageHelpers.language_name(lang)}
                  >
                    <%= LanguageHelpers.language_flag(lang) %> <%= String.upcase(lang) %>
                  </button>
                <% end %>
              </div>

              <!-- View Mode Toggle -->
              <div class="flex bg-gray-100 rounded-lg p-1">
                <button
                  phx-click="change_view"
                  phx-value-view="grid"
                  class={"px-3 py-1 rounded #{if @view_mode == "grid", do: "bg-white shadow-sm", else: ""}"}
                >
                  <Heroicons.squares_2x2 class="w-5 h-5" />
                </button>
                <button
                  phx-click="change_view"
                  phx-value-view="list"
                  class={"px-3 py-1 rounded #{if @view_mode == "list", do: "bg-white shadow-sm", else: ""}"}
                >
                  <Heroicons.list_bullet class="w-5 h-5" />
                </button>
              </div>

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

          <!-- Search Bar -->
          <div class="mt-4">
            <form phx-submit="search" class="relative">
              <input
                type="text"
                name="search"
                value={@filters.search}
                placeholder="Search events..."
                class="w-full px-4 py-3 pr-12 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
              <button type="submit" class="absolute right-3 top-3.5">
                <Heroicons.magnifying_glass class="w-5 h-5 text-gray-500" />
              </button>
            </form>
          </div>

          <!-- Quick Date Filters -->
          <div class="mt-4">
            <div class="flex items-center justify-between mb-2">
              <h2 class="text-sm font-medium text-gray-700">
                <%= gettext("Quick date filters") %>
              </h2>
              <%= if @active_date_range do %>
                <button
                  phx-click="clear_date_filter"
                  class="text-sm text-blue-600 hover:text-blue-800 flex items-center"
                >
                  <Heroicons.x_mark class="w-4 h-4 mr-1" />
                  <%= gettext("Clear date filter") %>
                </button>
              <% end %>
            </div>
            <div class="flex flex-wrap gap-2">
              <.date_range_button
                range={:all}
                label={gettext("All Events")}
                active={@active_date_range == nil}
                count={@all_events_count}
              />
              <.date_range_button
                range={:today}
                label={gettext("Today")}
                active={@active_date_range == :today}
                count={Map.get(@date_range_counts, :today, 0)}
              />
              <.date_range_button
                range={:tomorrow}
                label={gettext("Tomorrow")}
                active={@active_date_range == :tomorrow}
                count={Map.get(@date_range_counts, :tomorrow, 0)}
              />
              <.date_range_button
                range={:this_weekend}
                label={gettext("This Weekend")}
                active={@active_date_range == :this_weekend}
                count={Map.get(@date_range_counts, :this_weekend, 0)}
              />
              <.date_range_button
                range={:next_7_days}
                label={gettext("Next 7 Days")}
                active={@active_date_range == :next_7_days}
                count={Map.get(@date_range_counts, :next_7_days, 0)}
              />
              <.date_range_button
                range={:next_30_days}
                label={gettext("Next 30 Days")}
                active={@active_date_range == :next_30_days}
                count={Map.get(@date_range_counts, :next_30_days, 0)}
              />
              <.date_range_button
                range={:this_month}
                label={gettext("This Month")}
                active={@active_date_range == :this_month}
                count={Map.get(@date_range_counts, :this_month, 0)}
              />
              <.date_range_button
                range={:next_month}
                label={gettext("Next Month")}
                active={@active_date_range == :next_month}
                count={Map.get(@date_range_counts, :next_month, 0)}
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Filters Panel -->
      <div :if={@show_filters} class="bg-white border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <.filter_panel
            filters={@filters}
            radius_km={@radius_km}
            categories={@categories}
          />
        </div>
      </div>

      <!-- Active Filters -->
      <div :if={EventFilters.active_filter_count(@filters, 50) > 0} class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-4">
        <div class="flex items-center space-x-2">
          <span class="text-sm text-gray-600">Active filters:</span>
          <.active_filter_tags filters={@filters} radius_km={@radius_km} categories={@categories} active_date_range={@active_date_range} default_radius={50} />
          <button
            phx-click="clear_filters"
            class="ml-4 text-sm text-blue-600 hover:text-blue-800"
          >
            Clear all
          </button>
        </div>
      </div>

      <!-- Events Grid/List -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= if @loading or @events_loading do %>
          <!-- Skeleton Loading State -->
          <div class="animate-pulse">
            <!-- Results count skeleton -->
            <div class="mb-4">
              <div class="h-4 w-32 bg-gray-200 rounded"></div>
            </div>

            <!-- Event cards skeleton grid -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for _i <- 1..6 do %>
                <div class="bg-white rounded-lg shadow overflow-hidden">
                  <!-- Image placeholder -->
                  <div class="h-48 bg-gray-200"></div>
                  <!-- Content -->
                  <div class="p-4 space-y-3">
                    <!-- Title -->
                    <div class="h-5 bg-gray-200 rounded w-3/4"></div>
                    <!-- Date/time -->
                    <div class="flex items-center space-x-2">
                      <div class="h-4 w-4 bg-gray-300 rounded"></div>
                      <div class="h-4 bg-gray-200 rounded w-1/2"></div>
                    </div>
                    <!-- Location -->
                    <div class="flex items-center space-x-2">
                      <div class="h-4 w-4 bg-gray-300 rounded"></div>
                      <div class="h-4 bg-gray-200 rounded w-2/3"></div>
                    </div>
                    <!-- Category badge -->
                    <div class="flex space-x-2">
                      <div class="h-6 w-16 bg-gray-200 rounded-full"></div>
                      <div class="h-6 w-20 bg-gray-200 rounded-full"></div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- Pagination skeleton -->
            <div class="mt-8 flex justify-center">
              <div class="flex items-center space-x-2">
                <div class="h-10 w-20 bg-gray-200 rounded"></div>
                <div class="h-10 w-10 bg-gray-300 rounded"></div>
                <div class="h-10 w-10 bg-gray-200 rounded"></div>
                <div class="h-10 w-10 bg-gray-200 rounded"></div>
                <div class="h-10 w-20 bg-gray-200 rounded"></div>
              </div>
            </div>

            <p class="text-center text-sm text-gray-500 mt-4">Loading events...</p>
          </div>
        <% else %>
          <%= if @events == [] do %>
            <div class="text-center py-12">
              <Heroicons.calendar_days class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-lg font-medium text-gray-900">
                No events found
              </h3>
              <p class="mt-1 text-sm text-gray-500">
                Try adjusting your filters or search query
              </p>
            </div>
          <% else %>
            <div class="mb-4 text-sm text-gray-600">
              Found {@total_events} events
            </div>

            <%= if @view_mode == "grid" do %>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                <%= for item <- @events do %>
                  <%= cond do %>
                    <% match?(%AggregatedMovieGroup{}, item) -> %>
                      <.aggregated_movie_card group={item} language={@language} show_city={false} />
                    <% match?(%AggregatedContainerGroup{}, item) -> %>
                      <.aggregated_container_card group={item} language={@language} show_city={false} />
                    <% is_aggregated?(item) -> %>
                      <.aggregated_event_card group={item} language={@language} show_city={false} />
                    <% true -> %>
                      <.event_card event={item} language={@language} show_city={false} />
                  <% end %>
                <% end %>
              </div>
            <% else %>
              <div class="space-y-4">
                <%= for item <- @events do %>
                  <%= cond do %>
                    <% match?(%AggregatedMovieGroup{}, item) -> %>
                      <.aggregated_movie_card group={item} language={@language} show_city={false} />
                    <% match?(%AggregatedContainerGroup{}, item) -> %>
                      <.aggregated_container_card group={item} language={@language} show_city={false} />
                    <% is_aggregated?(item) -> %>
                      <.aggregated_event_card group={item} language={@language} show_city={false} />
                    <% true -> %>
                      <.event_card event={item} language={@language} show_city={false} />
                  <% end %>
                <% end %>
              </div>
            <% end %>

            <!-- Pagination -->
            <div class="mt-8">
              <.pagination pagination={@pagination} />
            </div>
          <% end %>
        <% end %>
      </div>

    </div>

    <div id="language-cookie-hook" phx-hook="LanguageCookie"></div>
    """
  end

  # Component: Filter Panel with radius selector
  defp filter_panel(assigns) do
    ~H"""
    <form phx-change="filter" class="space-y-6">
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <!-- Search Radius -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">
            Search Radius
          </label>
          <select
            name="filter[radius]"
            class="w-full px-3 py-2 border border-gray-300 rounded-md"
          >
            <option value="5" selected={@radius_km == 5}>5 km</option>
            <option value="10" selected={@radius_km == 10}>10 km</option>
            <option value="25" selected={@radius_km == 25}>25 km</option>
            <option value="50" selected={@radius_km == 50}>50 km</option>
            <option value="100" selected={@radius_km == 100}>100 km</option>
          </select>
        </div>

        <!-- Sort By -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">
            Sort By
          </label>
          <select
            name="filter[sort_by]"
            class="w-full px-3 py-2 border border-gray-300 rounded-md"
          >
            <option value="starts_at" selected={@filters.sort_by == :starts_at}>
              Date
            </option>
            <option value="distance" selected={@filters.sort_by == :distance}>
              Distance
            </option>
            <option value="title" selected={@filters.sort_by == :title}>
              Title
            </option>
          </select>
        </div>
      </div>

      <!-- Categories -->
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Categories
        </label>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
          <%= for category <- @categories do %>
            <label class="flex items-center space-x-2">
              <input
                type="checkbox"
                name="filter[categories][]"
                value={category.id}
                checked={category.id in @filters.categories}
                class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
              <span class="text-sm text-gray-700"><%= category.name %></span>
            </label>
          <% end %>
        </div>
      </div>
    </form>
    """
  end

  # Component: Pagination - EXACT same from Activities page
  defp pagination(assigns) do
    ~H"""
    <nav class="flex justify-center">
      <div class="flex items-center space-x-2">
        <!-- Previous -->
        <button
          :if={@pagination.page_number > 1}
          phx-click="paginate"
          phx-value-page={@pagination.page_number - 1}
          class="px-3 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
        >
          Previous
        </button>

        <!-- Page Numbers -->
        <div class="flex space-x-1">
          <%= for page <- Pagination.page_links(@pagination) do %>
            <%= if page == :ellipsis do %>
              <span class="px-3 py-2">...</span>
            <% else %>
              <button
                phx-click="paginate"
                phx-value-page={page}
                class={"px-3 py-2 rounded-md #{if page == @pagination.page_number, do: "bg-blue-600 text-white", else: "border border-gray-300 hover:bg-gray-50"}"}
              >
                <%= page %>
              </button>
            <% end %>
          <% end %>
        </div>

        <!-- Next -->
        <button
          :if={@pagination.page_number < @pagination.total_pages}
          phx-click="paginate"
          phx-value-page={@pagination.page_number + 1}
          class="px-3 py-2 border border-gray-300 rounded-md hover:bg-gray-50"
        >
          Next
        </button>
      </div>
    </nav>
    """
  end

  # Private functions

  defp fetch_events(socket) do
    start_time = System.monotonic_time(:millisecond)
    city = socket.assigns.city
    filters = socket.assigns.filters
    language = socket.assigns.language

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
    {geographic_events, total_count, all_events_count, date_range_counts} =
      if lat && lng do
        # Get the paginated events with aggregation enabled
        # For city pages, ignore city boundaries in aggregation since geographic
        # filtering already determines relevance. Use viewing city as canonical city.
        events =
          PublicEventsEnhanced.list_events_with_aggregation(
            query_filters
            |> Map.put(:aggregate, true)
            |> Map.put(:ignore_city_in_aggregation, true)
            |> Map.put(:viewing_city, city)
          )

        # Get the total count without pagination
        # Use raw count (not aggregation) to avoid 500-event limit and ensure consistency
        count_filters = Map.delete(query_filters, :page) |> Map.delete(:page_size)

        total = PublicEventsEnhanced.count_events(count_filters)

        # Get date range counts with geographic filtering, but without existing date filters
        # This ensures date range counts are calculated from ALL events, not just the currently filtered ones
        date_range_count_filters = EventFilters.build_date_range_count_filters(count_filters)

        # Use cached date range counts (5 min TTL) - cache key includes city slug and radius
        date_counts =
          CityPageCache.get_date_range_counts(
            city.slug,
            filters[:radius_km] || @default_radius_km,
            fn ->
              PublicEventsEnhanced.get_quick_date_range_counts(date_range_count_filters)
            end
          )

        # Get the count of ALL events (no date filters) for the "All Events" button
        # Use direct count (not aggregation-aware) to avoid 500-event limit issue
        # This ensures "All Events" is always >= any specific date range count
        all_events = PublicEventsEnhanced.count_events(date_range_count_filters)

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

  defp default_filters do
    # Default to next 30 days like public events page
    {start_date, end_date} = PublicEventsEnhanced.calculate_date_range(:next_30_days)

    %{
      search: nil,
      categories: [],
      start_date: start_date,
      end_date: end_date,
      radius_km: @default_radius_km,
      sort_by: :starts_at,
      sort_order: :asc,
      page: 1,
      # Divisible by 3 for grid layout (3 columns on large screens)
      page_size: 30,
      show_past: true
    }
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

    filters = %{
      search: params["search"],
      categories: category_ids,
      start_date: parse_date(params["start_date"]),
      end_date: parse_date(params["end_date"]),
      radius_km: parse_integer(params["radius"]) || socket.assigns.radius_km,
      sort_by: parse_sort(params["sort"]),
      sort_order: :asc,
      page: parse_integer(params["page"]) || 1,
      page_size: 21,
      show_past: parse_boolean(params["show_past"])
    }

    socket
    |> assign(:filters, filters)
    |> assign(:radius_km, filters.radius_km)
  end

  defp build_path(socket, filters) do
    params = build_filter_params(filters)
    ~p"/c/#{socket.assigns.city.slug}?#{params}"
  end

  defp build_filter_params(filters) do
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
  defp parse_sort("distance"), do: :distance
  defp parse_sort("title"), do: :title
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
    # Build absolute social card URL
    base_url = EventasaurusWeb.UrlHelper.build_url("", request_uri)
    image_url = "#{base_url}#{social_card_path}"

    # Wrap with CDN
    cdn_image_url = CDN.url(image_url)

    # Build canonical URL
    canonical_url = "#{base_url}/c/#{city.slug}"

    # Build description with stats
    description = meta_description(city)

    # Generate Open Graph tags
    Phoenix.HTML.Safe.to_iodata(
      OpenGraphComponent.open_graph_tags(%{
        type: "website",
        title: page_title(city),
        description: description,
        image_url: cdn_image_url,
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
