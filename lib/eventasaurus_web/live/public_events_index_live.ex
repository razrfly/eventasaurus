defmodule EventasaurusWeb.PublicEventsIndexLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusDiscovery.Categories
  alias EventasaurusWeb.Helpers.CategoryHelpers

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
      |> assign(:show_filters, false)
      |> assign(:loading, false)

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
    cleared_filters = default_filters()

    socket =
      socket
      |> assign(:filters, cleared_filters)
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
        sort_order: filters[:sort_order] || :asc
      })

    events = PublicEventsEnhanced.list_events(query_filters)

    total = PublicEventsEnhanced.count_events(filters)

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
    assign(socket, :filter_facets, facets)
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
      page_size: 21
    }

    assign(socket, :filters, filters)
  end

  defp default_filters do
    %{
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
      page_size: 21
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
    case Date.from_iso8601(date_str) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00])
      _ -> nil
    end
  end

  defp parse_sort(nil), do: :starts_at
  defp parse_sort("price"), do: :price
  defp parse_sort("title"), do: :title
  defp parse_sort("relevance"), do: :relevance
  defp parse_sort(_), do: :starts_at

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
      :page
    ])
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, []} -> true
      {_k, ""} -> true
      {:page, 1} -> true
      # Don't include default sort
      {:sort_by, :starts_at} -> true
      _ -> false
    end)
    |> Enum.map(fn
      {:categories, ids} when is_list(ids) -> {"categories", Enum.join(ids, ",")}
      {:start_date, date} -> {"start_date", Date.to_iso8601(DateTime.to_date(date))}
      {:end_date, date} -> {"end_date", Date.to_iso8601(DateTime.to_date(date))}
      {:min_price, price} -> {"min_price", to_string(price)}
      {:max_price, price} -> {"max_price", to_string(price)}
      {:city_id, id} -> {"city", to_string(id)}
      {:sort_by, sort} -> {"sort", to_string(sort)}
      {:page, page} -> {"page", to_string(page)}
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
                <%= if active_filter_count(@filters) > 0 do %>
                  <span class="ml-2 bg-blue-700 px-2 py-0.5 rounded-full text-xs">
                    <%= active_filter_count(@filters) %>
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
                placeholder={gettext("Search events...")}
                class="w-full px-4 py-3 pr-12 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              />
              <button type="submit" class="absolute right-3 top-3.5">
                <Heroicons.magnifying_glass class="w-5 h-5 text-gray-500" />
              </button>
            </form>
          </div>
        </div>
      </div>

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
      <div :if={active_filter_count(@filters) > 0} class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-4">
        <div class="flex items-center space-x-2">
          <span class="text-sm text-gray-600">Active filters:</span>
          <.active_filter_tags filters={@filters} categories={@categories} />
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
                <%= gettext("No events found") %>
              </h3>
              <p class="mt-1 text-sm text-gray-500">
                <%= gettext("Try adjusting your filters or search query") %>
              </p>
            </div>
          <% else %>
            <div class="mb-4 text-sm text-gray-600">
              <%= gettext("Found %{count} events", count: @pagination.total_entries) %>
            </div>

            <%= if @view_mode == "grid" do %>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                <.event_card :for={event <- @events} event={event} language={@language} />
              </div>
            <% else %>
              <div class="space-y-4">
                <.event_list_item :for={event <- @events} event={event} language={@language} />
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
            <option value="price" selected={@filters.sort_by == :price}>
              <%= gettext("Price") %>
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

  # Component: Event Card
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
                <%= gettext("Price not available") %>
              </span>
            </div>
          <% end %>
          --%>
        </div>
      </div>
    </.link>
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

  # Component: Pagination
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
          <%= gettext("Previous") %>
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
          <%= gettext("Next") %>
        </button>
      </div>
    </nav>
    """
  end

  # Component: Active Filter Tags
  defp active_filter_tags(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <%= if @filters.search do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          Search: <%= @filters.search %>
          <button phx-click="clear_search" class="ml-2">
            <Heroicons.x_mark class="w-3 h-3" />
          </button>
        </span>
      <% end %>

      <%= for category_id <- @filters.categories || [] do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          <%= get_category_name(@categories, category_id) %>
          <button phx-click="remove_category" phx-value-id={category_id} class="ml-2">
            <Heroicons.x_mark class="w-3 h-3" />
          </button>
        </span>
      <% end %>

      <!-- Add more filter tags as needed -->
    </div>
    """
  end

  # Helper Functions
  defp active_filter_count(filters) do
    count = 0
    count = if filters.search, do: count + 1, else: count
    count = if filters.categories != [], do: count + 1, else: count
    count = if filters.start_date, do: count + 1, else: count
    count = if filters.end_date, do: count + 1, else: count
    count = if filters.min_price, do: count + 1, else: count
    count = if filters.max_price, do: count + 1, else: count
    count
  end

  defp get_category_name(categories, id) do
    Enum.find_value(categories, fn cat ->
      if cat.id == id, do: cat.name
    end) || "Unknown"
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
end
