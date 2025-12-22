defmodule EventasaurusWeb.PublicEventsSearchLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusDiscovery.Categories
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup
  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusWeb.Live.Helpers.EventFilters
  alias Eventasaurus.CDN

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.Components.EventListing

  @impl true
  def mount(_params, _session, socket) do
    # Get language from session or default to English
    language = get_connect_params(socket)["locale"] || "en"

    socket =
      socket
      |> assign(:language, language)
      |> assign(:view_mode, "grid")
      |> assign(:filters, default_filters())
      |> assign(:categories, Categories.list_categories())
      |> assign(:filter_facets, %{})
      |> assign(:date_range_counts, %{})
      # Default: no date filter (show all events)
      |> assign(:active_date_range, nil)
      # Total events without date filter
      |> assign(:all_events_count, 0)
      |> assign(:show_filters, false)
      |> assign(:loading, false)
      |> assign(:group_by_date, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_params_to_filters(params)
      |> fetch_events()
      |> fetch_facets()

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
  def handle_event("filter", %{"filter" => filter_params}, socket) do
    # Parse the filter parameters and merge with existing filters
    current_filters = socket.assigns.filters

    new_filters = %{
      categories: parse_id_list(filter_params["categories"]),
      start_date: parse_date(filter_params["start_date"]),
      end_date: parse_date(filter_params["end_date"]),
      min_price: parse_decimal(filter_params["min_price"]),
      max_price: parse_decimal(filter_params["max_price"]),
      sort_by: parse_sort(filter_params["sort_by"]),
      sort_order: :asc,
      city_id: nil,
      # Keep existing search
      search: current_filters.search,
      # Reset to page 1 when filters change
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
  def handle_event("change_language", %{"language" => language}, socket) do
    socket =
      socket
      |> assign(:language, language)
      |> fetch_events()
      |> Phoenix.LiveView.push_event("set_language_cookie", %{language: language})

    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_category", %{"id" => category_id}, socket) do
    category_id = String.to_integer(category_id)
    current_categories = socket.assigns.filters.categories || []
    updated_categories = Enum.reject(current_categories, &(&1 == category_id))

    filters = Map.put(socket.assigns.filters, :categories, updated_categories)

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
  def handle_event("clear_filters", _params, socket) do
    # Clear all filters including date filters
    cleared_filters = %{
      search: nil,
      categories: [],
      start_date: nil,
      end_date: nil,
      min_price: nil,
      max_price: nil,
      city_id: nil,
      sort_by: :starts_at,
      sort_order: :asc,
      page: 1,
      page_size: 21,
      show_past: false
    }

    socket =
      socket
      |> assign(:filters, cleared_filters)
      |> assign(:active_date_range, nil)
      |> push_patch(
        to: build_path(%{socket | assigns: Map.put(socket.assigns, :filters, cleared_filters)})
      )

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
          |> push_patch(
            to: build_path(%{socket | assigns: Map.put(socket.assigns, :filters, filters)})
          )

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
      |> push_patch(
        to: build_path(%{socket | assigns: Map.put(socket.assigns, :filters, filters)})
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_date_grouping", _params, socket) do
    {:noreply, update(socket, :group_by_date, &(!&1))}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    updated_filters = Map.put(socket.assigns.filters, :page, page)

    socket =
      socket
      |> assign(:filters, updated_filters)
      |> push_patch(
        to: build_path(%{socket | assigns: Map.put(socket.assigns, :filters, updated_filters)})
      )

    {:noreply, socket}
  end

  defp fetch_events(socket) do
    filters = socket.assigns.filters
    language = socket.assigns.language

    # Ensure sort_order is included
    query_filters =
      Map.merge(filters, %{
        language: language,
        sort_order: filters[:sort_order] || :asc,
        # Enable aggregation on index
        aggregate: true
      })

    events = PublicEventsEnhanced.list_events_with_aggregation(query_filters)

    # Use count_events_with_aggregation to get accurate count of aggregated results
    total = PublicEventsEnhanced.count_events_with_aggregation(Map.put(filters, :aggregate, true))

    pagination = %Pagination{
      entries: events,
      page_number: filters.page,
      page_size: filters.page_size,
      total_entries: total,
      total_pages: ceil(total / filters.page_size)
    }

    assign(socket,
      events: events,
      pagination: pagination
    )
  end

  defp fetch_facets(socket) do
    # Fetch filter facets for displaying counts
    facets = PublicEventsEnhanced.get_filter_facets(socket.assigns.filters)

    # Use EventFilters helper to build date range count filters
    date_range_count_filters = EventFilters.build_date_range_count_filters(socket.assigns.filters)
    date_range_counts = PublicEventsEnhanced.get_quick_date_range_counts(date_range_count_filters)

    # Get count of ALL events (no date filters) for "All Events" button
    # Use aggregation-aware count to match what users actually see when browsing
    all_events_count = PublicEventsEnhanced.count_events_with_aggregation(date_range_count_filters)

    socket
    |> assign(:filter_facets, facets)
    |> assign(:date_range_counts, date_range_counts)
    |> assign(:all_events_count, all_events_count)
  end

  defp apply_params_to_filters(socket, params) do
    # Handle both singular category (slug from route) and plural categories (IDs from query)
    category_ids =
      case params do
        %{"category" => slug} when is_binary(slug) and slug != "" ->
          # Single category slug from route like /activities/category/concerts
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
      min_price: parse_decimal(params["min_price"]),
      max_price: parse_decimal(params["max_price"]),
      city_id: parse_integer(params["city"]),
      sort_by: parse_sort(params["sort"]),
      # Add default sort order
      sort_order: :asc,
      page: parse_integer(params["page"]) || 1,
      page_size: 21,
      # Parse show_past from URL params (defaults to false if not present)
      show_past: parse_boolean(params["show_past"])
    }

    assign(socket, :filters, filters)
  end

  defp default_filters do
    # Default to showing next 30 days of events
    {start_date, end_date} = PublicEventsEnhanced.calculate_date_range(:next_30_days)

    %{
      search: nil,
      categories: [],
      start_date: start_date,
      end_date: end_date,
      min_price: nil,
      max_price: nil,
      city_id: nil,
      sort_by: :starts_at,
      sort_order: :asc,
      page: 1,
      page_size: 21,
      # Default: show all events in the next 30 days range, even if they already started today
      show_past: true
    }
  end

  # Currently unused but kept for potential future use
  # defp parse_filter_params(params) do
  #   %{
  #     categories: parse_id_list(params["categories"]),
  #     start_date: parse_date(params["start_date"]),
  #     end_date: parse_date(params["end_date"]),
  #     min_price: parse_decimal(params["min_price"]),
  #     max_price: parse_decimal(params["max_price"]),
  #     city_id: parse_integer(params["city_id"]),
  #     sort_by: parse_sort(params["sort_by"])
  #   }
  # end

  defp parse_id_list(nil), do: []
  defp parse_id_list(""), do: []

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

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(val) when is_binary(val) do
    case Decimal.parse(val) do
      {dec, _} when is_struct(dec, Decimal) -> dec
      _ -> nil
    end
  end

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

  defp parse_sort(nil), do: :starts_at
  defp parse_sort("title"), do: :title
  defp parse_sort("relevance"), do: :relevance
  defp parse_sort(_), do: :starts_at

  defp parse_boolean(nil), do: false
  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean(_), do: false

  defp build_path(socket) do
    filters = socket.assigns.filters
    params = build_filter_params(filters)

    case socket.assigns[:live_action] do
      :search ->
        ~p"/activities/search?#{params}"

      :category ->
        case socket.assigns[:category] do
          nil -> ~p"/activities?#{params}"
          category -> ~p"/activities/category/#{category}?#{params}"
        end

      _ ->
        ~p"/activities?#{params}"
    end
  end

  defp build_filter_params(filters) do
    filters
    |> Map.take([
      :search,
      :categories,
      :start_date,
      :end_date,
      :min_price,
      :max_price,
      :city_id,
      :sort_by,
      :page,
      :show_past
    ])
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, []} -> true
      {_k, ""} -> true
      {:page, 1} -> true
      # Don't include default sort
      {:sort_by, :starts_at} -> true
      # Don't include default show_past value
      {:show_past, false} -> true
      _ -> false
    end)
    |> Enum.map(fn
      {:categories, ids} when is_list(ids) -> {"categories", Enum.join(ids, ",")}
      {:start_date, date} -> {"start_date", DateTime.to_iso8601(date)}
      {:end_date, date} -> {"end_date", DateTime.to_iso8601(date)}
      {:min_price, price} -> {"min_price", to_string(price)}
      {:max_price, price} -> {"max_price", to_string(price)}
      {:city_id, id} -> {"city", to_string(id)}
      {:sort_by, sort} -> {"sort", to_string(sort)}
      {:page, page} -> {"page", to_string(page)}
      {:show_past, val} -> {"show_past", to_string(val)}
      {k, v} -> {to_string(k), to_string(v)}
    end)
    |> Enum.into(%{})
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
              <%= gettext("Discover Events") %>
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
                <%= if EventFilters.active_filter_count(@filters) > 0 do %>
                  <span class="ml-2 bg-blue-700 px-2 py-0.5 rounded-full text-xs">
                    <%= EventFilters.active_filter_count(@filters) %>
                  </span>
                <% end %>
              </button>
            </div>
          </div>

          <!-- Search Bar -->
          <div class="mt-4">
            <.search_bar filters={@filters} />
          </div>
        </div>
      </div>

      <!-- Quick Date Range Filters -->
      <.quick_date_filters
        active_date_range={@active_date_range}
        date_range_counts={@date_range_counts}
        all_events_count={@all_events_count}
      />

      <!-- Filters Panel -->
      <div :if={@show_filters} class="bg-white border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <.filter_panel
            filters={@filters}
            categories={@categories}
            facets={@filter_facets}
          />
        </div>
      </div>

      <!-- Active Filters -->
      <div :if={EventFilters.active_filter_count(@filters) > 0} class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-4">
        <div class="flex items-center space-x-2">
          <span class="text-sm text-gray-600">Active filters:</span>
          <.active_filter_tags filters={@filters} categories={@categories} active_date_range={@active_date_range} />
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
          <.loading_skeleton />
        <% else %>
          <%= if @events == [] do %>
            <.empty_state />
          <% else %>
            <%= if @view_mode == "grid" do %>
              <.event_results
                events={@events}
                view_mode={@view_mode}
                language={@language}
                pagination={@pagination}
                show_city={true}
              />
            <% else %>
              <div class="mb-4 text-sm text-gray-600">
                <%= showing_range_text(@pagination, @events) %>
              </div>
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

  # Component: Filter Panel
  defp filter_panel(assigns) do
    ~H"""
    <form phx-change="filter" class="space-y-6">
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <!-- Categories -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">
            <%= gettext("Categories") %>
          </label>
          <div class="space-y-2 max-h-48 overflow-y-auto">
            <div :for={category <- @categories} class="flex items-center">
              <input
                type="checkbox"
                name="filter[categories][]"
                value={category.id}
                checked={category.id in (@filters.categories || [])}
                class="h-4 w-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
              />
              <label class="ml-2 text-sm text-gray-700">
                <%= category.name %>
                <span :if={get_facet_count(@facets, :categories, category.id)} class="text-gray-500">
                  (<%= get_facet_count(@facets, :categories, category.id) %>)
                </span>
              </label>
            </div>
          </div>
        </div>

        <!-- Date Range -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">
            <%= gettext("Date Range") %>
          </label>
          <input
            type="date"
            name="filter[start_date]"
            value={format_date(@filters.start_date)}
            class="w-full px-3 py-2 border border-gray-300 rounded-md"
          />
          <input
            type="date"
            name="filter[end_date]"
            value={format_date(@filters.end_date)}
            class="mt-2 w-full px-3 py-2 border border-gray-300 rounded-md"
          />
        </div>

        <%!-- Price filtering temporarily hidden - no APIs provide price data
             Infrastructure retained for future API support
             See GitHub issue #1281 for details
        <!-- Price Range -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">
            <%= gettext("Price Range") %>
          </label>
          <div class="flex space-x-2">
            <input
              type="number"
              name="filter[min_price]"
              value={@filters.min_price}
              placeholder="Min"
              class="w-full px-3 py-2 border border-gray-300 rounded-md"
            />
            <input
              type="number"
              name="filter[max_price]"
              value={@filters.max_price}
              placeholder="Max"
              class="w-full px-3 py-2 border border-gray-300 rounded-md"
            />
          </div>
        </div>
        --%>

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
            <option value="title" selected={@filters.sort_by == :title}>
              <%= gettext("Title") %>
            </option>
            <option value="relevance" selected={@filters.sort_by == :relevance}>
              <%= gettext("Relevance") %>
            </option>
          </select>
        </div>
      </div>
    </form>
    """
  end

  # Component: Event List Item
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
                <img src={CDN.url(Map.get(@event, :cover_image_url), width: 200, height: 200, fit: "cover", quality: 85)} alt={@event.title} class="w-full h-full object-cover" loading="lazy" referrerpolicy="no-referrer">
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
                <%= gettext("Price not available") %>
              </div>
            <% end %>
          </div>
          --%>
        </div>
      </div>
    </.link>
    """
  end

  # Helper Functions

  # Helper to check if an item is an aggregated group
  defp is_aggregated?(%{events: events}) when is_list(events) and length(events) > 1, do: true
  defp is_aggregated?(_), do: false

  # Generate "Showing X-Y of Z events" text for list view
  defp showing_range_text(pagination, events) do
    total = pagination.total_entries
    page_number = pagination.page_number
    page_size = pagination.page_size
    current_page_count = length(events)

    if total <= page_size do
      # Single page - show actual count displayed
      gettext("Showing %{count} events", count: current_page_count)
    else
      start_idx = (page_number - 1) * page_size + 1
      # Use actual displayed count for end index
      end_idx = start_idx + current_page_count - 1

      gettext("Showing %{start}-%{end} of %{total} events",
        start: start_idx,
        end: end_idx,
        total: total
      )
    end
  end

  defp get_facet_count(facets, type, id) do
    facets[type]
    |> Enum.find(fn item -> item.id == id end)
    |> case do
      nil -> nil
      item -> item.count
    end
  end

  defp format_datetime(nil), do: "TBD"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  defp format_date(nil), do: nil

  defp format_date(datetime) do
    Date.to_iso8601(DateTime.to_date(datetime))
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
  #       "Free"
  #   end
  # end

  # Component: Aggregated Event Group List Item (List View)
  defp aggregated_list_item(
         %{group: %EventasaurusDiscovery.Movies.AggregatedMovieGroup{}} = assigns
       ) do
    alias EventasaurusDiscovery.Movies.AggregatedMovieGroup

    ~H"""
    <.link navigate={AggregatedMovieGroup.path(@group)} class="block">
      <div class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow p-4 flex gap-4 ring-2 ring-blue-500 ring-offset-2">
        <!-- Movie Backdrop -->
        <div class="flex-shrink-0 w-48 h-32 bg-gray-200 rounded relative overflow-hidden">
          <%= if @group.movie_backdrop_url do %>
            <img src={CDN.url(@group.movie_backdrop_url, width: 400, height: 300, fit: "cover", quality: 85)} alt={@group.movie_title} class="w-full h-full object-cover" loading="lazy" referrerpolicy="no-referrer">
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <Heroicons.film class="w-12 h-12 text-gray-400" />
            </div>
          <% end %>
        </div>

        <!-- Movie Details -->
        <div class="flex-grow">
          <div class="flex items-start justify-between">
            <div>
              <h3 class="font-semibold text-lg text-gray-900">
                <%= AggregatedMovieGroup.title(@group) %>
              </h3>

              <div class="mt-1 flex items-center text-sm text-blue-600 font-medium">
                <Heroicons.calendar class="w-4 h-4 mr-1" />
                Movie Screenings
              </div>

              <div class="mt-1 flex items-center text-sm text-gray-600">
                <Heroicons.building_storefront class="w-4 h-4 mr-1" />
                <%= AggregatedMovieGroup.description(@group) %>
              </div>

              <div class="mt-1 flex items-center text-sm text-gray-600">
                <Heroicons.map_pin class="w-4 h-4 mr-1" />
                <%= @group.city.name %>
              </div>
            </div>

            <!-- Badge -->
            <div class="flex-shrink-0">
              <div class="bg-blue-500 text-white px-3 py-1 rounded-md text-xs font-medium flex items-center">
                <Heroicons.film class="w-3 h-3 mr-1" />
                <%= @group.screening_count %> screenings
              </div>
            </div>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp aggregated_list_item(assigns) do
    alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup

    ~H"""
    <.link navigate={AggregatedEventGroup.path(@group)} class="block">
      <div class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow p-4 flex gap-4 ring-2 ring-green-500 ring-offset-2">
        <!-- Event Image -->
        <div class="flex-shrink-0 w-48 h-32 bg-gray-200 rounded relative overflow-hidden">
          <%= if @group.cover_image_url do %>
            <img src={CDN.url(@group.cover_image_url, width: 400, height: 300, fit: "cover", quality: 85)} alt={@group.source_name} class="w-full h-full object-cover" loading="lazy" referrerpolicy="no-referrer">
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
              </svg>
            </div>
          <% end %>
        </div>

        <!-- Event Details -->
        <div class="flex-grow">
          <div class="flex items-start justify-between">
            <div>
              <h3 class="font-semibold text-lg text-gray-900">
                <%= AggregatedEventGroup.title(@group) %>
              </h3>

              <div class="mt-1 flex items-center text-sm text-green-600 font-medium">
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

            <!-- Badge -->
            <div class="flex-shrink-0">
              <div class="bg-green-500 text-white px-3 py-1 rounded-md text-xs font-medium flex items-center">
                <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
                </svg>
                <%= @group.event_count %> events
              </div>
            </div>
          </div>
        </div>
      </div>
    </.link>
    """
  end
end
