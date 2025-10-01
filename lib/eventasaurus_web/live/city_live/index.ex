defmodule EventasaurusWeb.CityLive.Index do
  @moduledoc """
  LiveView for city-based event discovery pages.

  Displays events within a configurable radius of a city's center,
  using the city's dynamically calculated coordinates.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup
  alias EventasaurusWeb.Helpers.CategoryHelpers
  alias EventasaurusWeb.Live.Helpers.EventFilters

  import EventasaurusWeb.EventComponents

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
          language = get_connect_params(socket)["locale"] || "en"

          {:ok,
           socket
           |> assign(:city, city)
           |> assign(:language, language)
           |> assign(:radius_km, @default_radius_km)
           |> assign(:view_mode, "grid")
           |> assign(:filters, default_filters())
           |> assign(:show_filters, false)
           |> assign(:loading, false)
           |> assign(:total_events, 0)
           |> assign(:all_events_count, 0)
           |> assign(:page_title, page_title(city))
           |> assign(:meta_description, meta_description(city))
           |> assign(:categories, Categories.list_categories())
           |> assign(:events, [])
           |> assign(:pagination, %Pagination{entries: [], page_number: 1, page_size: 60, total_entries: 0, total_pages: 0})
           |> assign(:active_date_range, nil)
           |> assign(:date_range_counts, %{})
           |> fetch_events()
           |> fetch_nearby_cities()}
        else
          {:ok,
           socket
           |> put_flash(:error, "City location data is being processed. Please try again later.")
           |> push_navigate(to: ~p"/activities")}
        end
    end
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
      |> push_patch(to: build_path(socket, filters))

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    filters = Map.put(socket.assigns.filters, :search, nil)

    socket =
      socket
      |> assign(:filters, filters)
      |> fetch_events()
      |> push_patch(to: build_path(socket, filters))

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

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:radius_km, radius_km)
      |> fetch_events()
      |> push_patch(to: build_path(socket, filters))

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
      page_size: 60,
      show_past: false
    }

    socket =
      socket
      |> assign(:filters, cleared_filters)
      |> assign(:radius_km, @default_radius_km)
      |> assign(:active_date_range, nil)
      |> fetch_events()
      |> push_patch(to: build_path(socket, cleared_filters))

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
    socket =
      socket
      |> assign(:language, language)
      |> fetch_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    updated_filters = Map.put(socket.assigns.filters, :page, page)

    socket =
      socket
      |> assign(:filters, updated_filters)
      |> fetch_events()
      |> push_patch(to: build_path(socket, updated_filters))

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

        socket =
          socket
          |> assign(:filters, filters)
          |> assign(:active_date_range, active_date_range)
          |> fetch_events()
          |> push_patch(to: build_path(socket, filters))

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

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:active_date_range, nil)
      |> fetch_events()
      |> push_patch(to: build_path(socket, filters))

    {:noreply, socket}
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
              <!-- Language Switcher -->
              <div class="flex bg-gray-100 rounded-lg p-1">
                <button
                  phx-click="change_language"
                  phx-value-language="en"
                  class={"px-3 py-1.5 rounded text-sm font-medium transition-colors #{if @language == "en", do: "bg-white shadow-sm text-blue-600", else: "text-gray-600 hover:text-gray-900"}"}
                  title="English"
                >
                  🇬🇧 EN
                </button>
                <button
                  phx-click="change_language"
                  phx-value-language="pl"
                  class={"px-3 py-1.5 rounded text-sm font-medium transition-colors #{if @language == "pl", do: "bg-white shadow-sm text-blue-600", else: "text-gray-600 hover:text-gray-900"}"}
                  title="Polski"
                >
                  🇵🇱 PL
                </button>
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
        <%= if @loading do %>
          <div class="flex justify-center py-12">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
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
                  <%= if is_aggregated?(item) do %>
                    <.aggregated_card group={item} language={@language} />
                  <% else %>
                    <.event_card event={item} language={@language} />
                  <% end %>
                <% end %>
              </div>
            <% else %>
              <div class="space-y-4">
                <%= for item <- @events do %>
                  <%= if is_aggregated?(item) do %>
                    <.aggregated_list_item group={item} language={@language} />
                  <% else %>
                    <.event_list_item event={item} language={@language} />
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

  # EXACT same event_card component from Activities page with multi-occurrence indicators
  defp event_card(assigns) do
    alias EventasaurusDiscovery.PublicEvents.PublicEvent

    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block">
      <div class={"bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow #{if PublicEvent.recurring?(@event), do: "ring-2 ring-green-500 ring-offset-2", else: ""}"}>
        <!-- Event Image -->
        <div class="h-48 bg-gray-200 rounded-t-lg relative overflow-hidden">
          <%= if Map.get(@event, :cover_image_url) do %>
            <img src={Map.get(@event, :cover_image_url)} alt={@event.title} class="w-full h-full object-cover" loading="lazy">
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
              </svg>
            </div>
          <% end %>

          <%= if @event.categories && @event.categories != [] do %>
            <% category = CategoryHelpers.get_preferred_category(@event.categories) %>
            <%= if category && category.color do %>
              <div
                class="absolute top-3 left-3 px-2 py-1 rounded-md text-xs font-medium text-white"
                style={"background-color: #{category.color}"}
              >
                <%= category.name %>
              </div>
            <% end %>
          <% end %>

          <!-- Recurring Event Badge -->
          <%= if PublicEvent.recurring?(@event) do %>
            <div class="absolute top-3 right-3 bg-green-500 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center">
              <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
              </svg>
              <%= PublicEvent.occurrence_count(@event) %> dates
            </div>
          <% end %>
        </div>

        <!-- Event Details -->
        <div class="p-4">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-2">
            <%= @event.display_title || @event.title %>
          </h3>

          <div class="mt-2 flex items-center text-sm text-gray-600">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= if PublicEvent.recurring?(@event) do %>
              <span class="text-green-600 font-medium">
                <%= PublicEvent.frequency_label(@event) %> • Next: <%= format_datetime(PublicEvent.next_occurrence_date(@event)) %>
              </span>
            <% else %>
              <%= format_datetime(@event.starts_at) %>
            <% end %>
          </div>

          <%= if @event.venue do %>
            <div class="mt-1 flex items-center text-sm text-gray-600">
              <Heroicons.map_pin class="w-4 h-4 mr-1" />
              <%= @event.venue.name %>
            </div>
          <% end %>

          <%!-- Price display temporarily hidden - no APIs provide price data
               Infrastructure retained for future API support
               See GitHub issue #1281 for details
          <%= if @event.min_price || @event.max_price do %>
            <div class="mt-2">
              <span class="text-sm font-medium text-gray-900">
                <%= format_price_range(@event) %>
              </span>
            </div>
          <% else %>
            <div class="mt-2">
              <span class="text-sm font-medium text-gray-500">
                Price not available
              </span>
            </div>
          <% end %>
          --%>
        </div>
      </div>
    </.link>
    """
  end

  # EXACT same event_list_item component from Activities page with multi-occurrence indicators
  defp event_list_item(assigns) do
    alias EventasaurusDiscovery.PublicEvents.PublicEvent

    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block">
      <div class={"bg-white rounded-lg shadow hover:shadow-md transition-shadow p-6 #{if PublicEvent.recurring?(@event), do: "border-l-4 border-green-500", else: ""}"}>
        <div class="flex gap-6">
          <!-- Event Image -->
          <div class="flex-shrink-0">
            <div class="w-24 h-24 bg-gray-200 rounded-lg overflow-hidden relative">
              <%= if Map.get(@event, :cover_image_url) do %>
                <img src={Map.get(@event, :cover_image_url)} alt={@event.title} class="w-full h-full object-cover" loading="lazy">
              <% else %>
                <div class="w-full h-full flex items-center justify-center">
                  <svg class="w-8 h-8 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
                  </svg>
                </div>
              <% end %>

              <!-- Stacked effect for recurring events -->
              <%= if PublicEvent.recurring?(@event) do %>
                <div class="absolute -bottom-1 -right-1 w-full h-full bg-white rounded-lg shadow -z-10"></div>
                <div class="absolute -bottom-2 -right-2 w-full h-full bg-white rounded-lg shadow -z-20"></div>
              <% end %>
            </div>
          </div>

          <div class="flex-1">
            <div class="flex items-start justify-between">
              <h3 class="text-xl font-semibold text-gray-900">
                <%= @event.display_title || @event.title %>
              </h3>

              <%= if PublicEvent.recurring?(@event) do %>
                <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                  <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M4 4a2 2 0 00-2 2v4a2 2 0 002 2V6h10a2 2 0 00-2-2H4zm2 6a2 2 0 012-2h8a2 2 0 012 2v4a2 2 0 01-2 2H8a2 2 0 01-2-2v-4zm6 4a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd" />
                  </svg>
                  <%= PublicEvent.occurrence_count(@event) %> dates
                </span>
              <% end %>
            </div>

            <div class="mt-2 flex flex-wrap gap-4 text-sm text-gray-600">
              <div class="flex items-center">
                <Heroicons.calendar class="w-4 h-4 mr-1" />
                <%= if PublicEvent.recurring?(@event) do %>
                  <span class="text-green-600 font-medium">
                    <%= PublicEvent.frequency_label(@event) %> • Next: <%= format_datetime(PublicEvent.next_occurrence_date(@event)) %>
                  </span>
                <% else %>
                  <%= format_datetime(@event.starts_at) %>
                <% end %>
              </div>

              <div class="flex items-center">
                <Heroicons.map_pin class="w-4 h-4 mr-1" />
                <%= @event.venue.name %>
              </div>

              <%= if @event.categories != [] do %>
                <div class="flex items-center">
                  <Heroicons.tag class="w-4 h-4 mr-1" />
                  <%= Enum.map_join(@event.categories, ", ", & &1.name) %>
                </div>
              <% end %>
            </div>

            <%= if @event.display_description do %>
              <p class="mt-3 text-gray-600 line-clamp-2">
                <%= @event.display_description %>
              </p>
            <% end %>
          </div>

          <%!-- Price display temporarily hidden - no APIs provide price data
               Infrastructure retained for future API support
               See GitHub issue #1281 for details
          <div class="ml-6 text-right">
            <%= if @event.min_price || @event.max_price do %>
              <div class="text-lg font-semibold text-gray-900">
                <%= format_price_range(@event) %>
              </div>
            <% else %>
              <div class="text-lg font-semibold text-gray-500">
                Price not available
              </div>
            <% end %>
          </div>
          --%>
        </div>
      </div>
    </.link>
    """
  end

  # Private functions

  defp fetch_events(socket) do
    city = socket.assigns.city
    filters = socket.assigns.filters
    language = socket.assigns.language

    # Get city coordinates
    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    # Build query filters with geographic filtering at database level
    query_filters = Map.merge(filters, %{
      language: language,
      sort_order: filters[:sort_order] || :asc,
      page_size: filters[:page_size] || 60,  # Use filter's page_size, default to 60 (divisible by 3)
      page: filters[:page] || 1,
      # Add geographic filtering parameters
      center_lat: lat,
      center_lng: lng,
      radius_km: filters[:radius_km] || @default_radius_km
    })

    # Get events with geographic filtering done at database level
    {geographic_events, total_count, all_events_count, date_range_counts} = if lat && lng do
      # Get the paginated events with aggregation enabled
      events = PublicEventsEnhanced.list_events_with_aggregation(Map.put(query_filters, :aggregate, true))

      # Get the total count without pagination
      # Use count_events_with_aggregation to get accurate count of aggregated results
      count_filters = Map.delete(query_filters, :page) |> Map.delete(:page_size)
      total = PublicEventsEnhanced.count_events_with_aggregation(Map.put(count_filters, :aggregate, true))

      # Get date range counts with geographic filtering, but without existing date filters
      # This ensures date range counts are calculated from ALL events, not just the currently filtered ones
      date_range_count_filters = EventFilters.build_date_range_count_filters(count_filters)
      date_counts = PublicEventsEnhanced.get_quick_date_range_counts(date_range_count_filters)

      # Get the count of ALL events (no date filters) for the "All Events" button
      # Use aggregation-aware count here as well
      all_events = PublicEventsEnhanced.count_events_with_aggregation(Map.put(date_range_count_filters, :aggregate, true))

      {events, total, all_events, date_counts}
    else
      # No coordinates, fallback to empty list
      {[], 0, 0, %{}}
    end

    # Use actual counts for pagination
    page = filters[:page] || 1
    page_size = filters[:page_size] || 60
    total_entries = total_count
    total_pages = ceil(total_entries / page_size)

    pagination = %Pagination{
      entries: geographic_events,
      page_number: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }

    socket
    |> assign(:events, geographic_events)
    |> assign(:pagination, pagination)
    |> assign(:total_events, total_entries)  # Use the total from pagination, not current page length
    |> assign(:all_events_count, all_events_count)  # Count of all events (no date filter)
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

  defp parse_id_list(nil), do: []
  defp parse_id_list([]), do: []
  defp parse_id_list(ids) when is_list(ids) do
    ids
    |> Enum.map(fn id ->
      case id do
        id when is_integer(id) -> id
        id when is_binary(id) ->
          case Integer.parse(id) do
            {num, _} -> num
            _ -> nil
          end
        _ -> nil
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

  defp format_datetime(nil), do: "TBD"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
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
      page_size: 60,  # Divisible by 3 for grid layout
      show_past: true
    }
  end

  defp apply_params_to_filters(socket, params) do
    filters = %{
      search: params["search"],
      categories: parse_id_list(params["categories"]),
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
    |> Map.take([:search, :categories, :start_date, :end_date, :radius_km, :sort_by, :page, :show_past])
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, ""} -> true
      {_k, []} -> true  # Empty categories list
      {:page, 1} -> true
      {:radius_km, @default_radius_km} -> true  # Don't include default radius
      {:sort_by, :starts_at} -> true
      {:show_past, false} -> true  # Don't include default
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

  # Check if an item is an aggregated event group
  defp is_aggregated?(%AggregatedEventGroup{}), do: true
  defp is_aggregated?(_), do: false

  # Aggregated card component for grid view
  defp aggregated_card(assigns) do
    ~H"""
    <.link navigate={AggregatedEventGroup.path(@group)} class="block">
      <div class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow ring-2 ring-green-500 ring-offset-2">
        <!-- Event Image -->
        <div class="h-48 bg-gray-200 rounded-t-lg relative overflow-hidden">
          <%= if @group.cover_image_url do %>
            <img src={@group.cover_image_url} alt={@group.source_name} class="w-full h-full object-cover" loading="lazy">
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
              </svg>
            </div>
          <% end %>

          <%= if @group.categories && @group.categories != [] do %>
            <% category = CategoryHelpers.get_preferred_category(@group.categories) %>
            <%= if category && category.color do %>
              <div class="absolute top-3 left-3 px-2 py-1 rounded-md text-xs font-medium text-white" style={"background-color: #{category.color}"}>
                <%= category.name %>
              </div>
            <% end %>
          <% end %>

          <!-- Aggregated Badge -->
          <div class="absolute top-3 right-3 bg-green-500 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center">
            <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
            </svg>
            <%= @group.event_count %> events
          </div>
        </div>

        <!-- Event Details -->
        <div class="p-4">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-2">
            <%= AggregatedEventGroup.title(@group) %>
          </h3>

          <div class="mt-2 flex items-center text-sm text-green-600 font-medium">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= String.capitalize(@group.aggregation_type) %>
          </div>

          <div class="mt-1 flex items-center text-sm text-gray-600">
            <Heroicons.building_storefront class="w-4 h-4 mr-1" />
            <%= AggregatedEventGroup.description(@group) %>
          </div>

          <div class="mt-1 flex items-center text-sm text-gray-600">
            <Heroicons.map_pin class="w-4 h-4 mr-1" />
            <%= @group.city.name %>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  # Aggregated list item component for list view
  defp aggregated_list_item(assigns) do
    ~H"""
    <.link navigate={AggregatedEventGroup.path(@group)} class="block">
      <div class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow p-4 flex gap-4 ring-2 ring-green-500 ring-offset-2">
        <!-- Event Image -->
        <div class="flex-shrink-0 w-32 h-32 bg-gray-200 rounded-lg relative overflow-hidden">
          <%= if @group.cover_image_url do %>
            <img src={@group.cover_image_url} alt={@group.source_name} class="w-full h-full object-cover" loading="lazy">
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <svg class="w-8 h-8 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
              </svg>
            </div>
          <% end %>

          <%= if @group.categories && @group.categories != [] do %>
            <% category = CategoryHelpers.get_preferred_category(@group.categories) %>
            <%= if category && category.color do %>
              <div class="absolute top-2 left-2 px-2 py-0.5 rounded text-xs font-medium text-white" style={"background-color: #{category.color}"}>
                <%= category.name %>
              </div>
            <% end %>
          <% end %>

          <!-- Aggregated Badge -->
          <div class="absolute top-2 right-2 bg-green-500 text-white px-1.5 py-0.5 rounded text-xs font-medium flex items-center">
            <svg class="w-3 h-3 mr-0.5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
            </svg>
            <%= @group.event_count %>
          </div>
        </div>

        <!-- Event Details -->
        <div class="flex-1 min-w-0">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-1">
            <%= AggregatedEventGroup.title(@group) %>
          </h3>

          <div class="mt-2 flex items-center text-sm text-green-600 font-medium">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= String.capitalize(@group.aggregation_type) %>
          </div>

          <div class="mt-1 flex items-center text-sm text-gray-600">
            <Heroicons.building_storefront class="w-4 h-4 mr-1" />
            <%= AggregatedEventGroup.description(@group) %>
          </div>

          <div class="mt-1 flex items-center text-sm text-gray-600">
            <Heroicons.map_pin class="w-4 h-4 mr-1" />
            <%= @group.city.name %>
          </div>
        </div>
      </div>
    </.link>
    """
  end
end