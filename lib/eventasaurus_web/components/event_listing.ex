defmodule EventasaurusWeb.Components.EventListing do
  @moduledoc """
  Unified event listing LiveComponent for displaying filtered, tiered events.

  This component provides consistent event display across venue, performer, city,
  and activities pages with configurable constraints and display options.

  ## Constraint Types

  The component supports various constraint types:

    * `{:venue_id, id}` - Filter events by venue
    * `{:performer_id, id}` - Filter events by performer
    * `{:city_id, id}` - Filter events by city
    * `{:radius, %{lat: lat, lng: lng, km: km}}` - Geographic radius filtering
    * `:global` - No constraint (all events)

  ## Example Usage

      <.live_component
        module={EventListing}
        id="venue-events"
        constraint={:venue_id, @venue.id}
        language={@language}
        empty_message="No upcoming events at this venue"
      />

  ## Tier Configuration

  Events are grouped into tiers based on their start date:
    * `short_term` - Events within the next 7 days
    * `near_term` - Events within 8-30 days
    * `future` - Events more than 30 days away
  """

  use EventasaurusWeb, :live_component
  require Logger

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup

  import EventasaurusWeb.Components.EventCards

  # Default tier configuration
  @default_tier_config [
    %{key: :short_term, label: "This Week", days: 7},
    %{key: :near_term, label: "This Month", days: 30},
    %{key: :future, label: "Coming Up", days: nil}
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, true)
     |> assign(:events, %{short_term: [], near_term: [], future: []})
     |> assign(:past_events, [])
     |> assign(:total_count, 0)
     |> assign(:past_count, 0)
     |> assign(:show_future, false)
     |> assign(:show_past_events, false)
     |> assign(:visible_counts, %{short_term: 9, near_term: 9, future: 9, past: 9})
     |> assign(:page_size, 9)
     |> assign(:filters, %{})
     |> assign(:search_query, "")
     |> assign(:sort_by, :starts_at)
     |> assign(:sort_order, :asc)}
  end

  @impl true
  def update(assigns, socket) do
    # Extract assigns with defaults
    constraint = Map.get(assigns, :constraint)
    language = Map.get(assigns, :language, "en")
    show_city = Map.get(assigns, :show_city, false)
    empty_message = Map.get(assigns, :empty_message, "No upcoming events")
    tier_config = Map.get(assigns, :tier_config, @default_tier_config)
    enable_aggregation = Map.get(assigns, :enable_aggregation, true)
    filters = Map.get(assigns, :filters, %{})

    # Feature toggles for optional UI elements
    show_search = Map.get(assigns, :show_search, false)
    show_sort = Map.get(assigns, :show_sort, false)
    show_past_toggle = Map.get(assigns, :show_past_toggle, false)
    sort_options = Map.get(assigns, :sort_options, [:starts_at, :title])

    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:constraint, constraint)
      |> assign(:language, language)
      |> assign(:show_city, show_city)
      |> assign(:empty_message, empty_message)
      |> assign(:tier_config, tier_config)
      |> assign(:enable_aggregation, enable_aggregation)
      |> assign(:filters, filters)
      |> assign(:show_search, show_search)
      |> assign(:show_sort, show_sort)
      |> assign(:show_past_toggle, show_past_toggle)
      |> assign(:sort_options, sort_options)

    # Fetch events if constraint changed, filters changed, or first load
    if socket.assigns.loading or constraint_changed?(socket, constraint) or
         filters_changed?(socket, filters) do
      socket = fetch_and_tier_events(socket)
      {:ok, assign(socket, :loading, false)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("toggle_future", _params, socket) do
    {:noreply, assign(socket, :show_future, !socket.assigns.show_future)}
  end

  @impl true
  def handle_event("toggle_past_events", _params, socket) do
    new_show_past = !socket.assigns.show_past_events

    socket =
      socket
      |> assign(:show_past_events, new_show_past)
      |> fetch_and_tier_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", %{"tier" => tier}, socket) do
    tier_atom = String.to_existing_atom(tier)
    current_counts = socket.assigns.visible_counts
    new_count = Map.get(current_counts, tier_atom, 9) + socket.assigns.page_size
    new_counts = Map.put(current_counts, tier_atom, new_count)
    {:noreply, assign(socket, :visible_counts, new_counts)}
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    # Update internal search state and notify parent via filters
    search_term = String.trim(search_term)
    search_term = if search_term == "", do: nil, else: search_term

    socket =
      socket
      |> assign(:search_query, search_term || "")
      |> update_filters_with_search(search_term)
      |> fetch_and_tier_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    socket =
      socket
      |> assign(:search_query, "")
      |> update_filters_with_search(nil)
      |> fetch_and_tier_events()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_change", %{"sort_by" => sort_by}, socket) do
    sort_atom = parse_sort_option(sort_by)

    socket =
      socket
      |> assign(:sort_by, sort_atom)
      |> update_filters_with_sort(sort_atom)
      |> fetch_and_tier_events()

    {:noreply, socket}
  end

  defp update_filters_with_search(socket, search_term) do
    filters = Map.put(socket.assigns.filters, :search, search_term)
    assign(socket, :filters, filters)
  end

  defp update_filters_with_sort(socket, sort_by) do
    filters = Map.put(socket.assigns.filters, :sort_by, sort_by)
    assign(socket, :filters, filters)
  end

  defp parse_sort_option("starts_at"), do: :starts_at
  defp parse_sort_option("title"), do: :title
  defp parse_sort_option("distance"), do: :distance
  defp parse_sort_option(_), do: :starts_at

  @impl true
  def render(assigns) do
    # Determine if we have active date filters
    has_date_filter =
      Map.has_key?(assigns.filters, :start_date) and not is_nil(assigns.filters[:start_date])

    # Check if search is active
    has_search = assigns.search_query != "" and assigns.search_query != nil

    assigns =
      assigns
      |> assign(:has_date_filter, has_date_filter)
      |> assign(:has_search, has_search)

    ~H"""
    <div class="event-listing" id={@id}>
      <%!-- Optional Search, Sort, and Past Events Controls --%>
      <%= if @show_search or @show_sort or @show_past_toggle do %>
        <.search_sort_controls
          show_search={@show_search}
          show_sort={@show_sort}
          show_past_toggle={@show_past_toggle}
          show_past_events={@show_past_events}
          past_count={@past_count}
          search_query={@search_query}
          sort_by={@sort_by}
          sort_options={@sort_options}
          has_search={@has_search}
          myself={@myself}
        />
      <% end %>

      <%= if @loading do %>
        <.loading_skeleton />
      <% else %>
        <%= if @has_date_filter or @has_search do %>
          <.flat_event_list
            events={@events}
            language={@language}
            show_city={@show_city}
            empty_message={@empty_message}
            visible_counts={@visible_counts}
            myself={@myself}
          />
        <% else %>
          <.event_tiers
            events={@events}
            past_events={@past_events}
            tier_config={@tier_config}
            language={@language}
            show_city={@show_city}
            empty_message={@empty_message}
            show_future={@show_future}
            show_past_events={@show_past_events}
            show_past_toggle={@show_past_toggle}
            visible_counts={@visible_counts}
            myself={@myself}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  # Search and Sort Controls Component
  defp search_sort_controls(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-6">
      <div class="flex flex-col sm:flex-row gap-4">
        <%!-- Search Input --%>
        <%= if @show_search do %>
          <div class="flex-1">
            <form phx-submit="search" phx-target={@myself} class="relative">
              <input
                type="text"
                name="search"
                value={@search_query}
                placeholder={gettext("Search events...")}
                class="w-full px-4 py-2 pr-20 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
              />
              <div class="absolute right-2 top-1/2 -translate-y-1/2 flex items-center gap-1">
                <%= if @has_search do %>
                  <button
                    type="button"
                    phx-click="clear_search"
                    phx-target={@myself}
                    class="p-1 text-gray-400 hover:text-gray-600"
                    title={gettext("Clear search")}
                  >
                    <Heroicons.x_mark class="w-4 h-4" />
                  </button>
                <% end %>
                <button type="submit" class="p-1 text-gray-500 hover:text-indigo-600">
                  <Heroicons.magnifying_glass class="w-5 h-5" />
                </button>
              </div>
            </form>
          </div>
        <% end %>

        <%!-- Sort Dropdown --%>
        <%= if @show_sort do %>
          <div class="sm:w-48">
            <form phx-change="sort_change" phx-target={@myself}>
              <select
                name="sort_by"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
              >
                <%= for option <- @sort_options do %>
                  <option value={option} selected={@sort_by == option}>
                    <%= sort_option_label(option) %>
                  </option>
                <% end %>
              </select>
            </form>
          </div>
        <% end %>

        <%!-- Past Events Toggle --%>
        <%= if @show_past_toggle do %>
          <div class="flex items-center">
            <button
              type="button"
              phx-click="toggle_past_events"
              phx-target={@myself}
              class={"inline-flex items-center px-3 py-2 text-sm font-medium rounded-lg transition-colors #{if @show_past_events, do: "bg-indigo-100 text-indigo-700 border border-indigo-300", else: "bg-gray-100 text-gray-600 border border-gray-300 hover:bg-gray-200"}"}
            >
              <Heroicons.clock class="w-4 h-4 mr-2" />
              <%= gettext("Past Events") %>
              <%= if @past_count > 0 do %>
                <span class={"ml-2 px-2 py-0.5 text-xs rounded-full #{if @show_past_events, do: "bg-indigo-200 text-indigo-800", else: "bg-gray-200 text-gray-600"}"}>
                  <%= @past_count %>
                </span>
              <% end %>
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp sort_option_label(:starts_at), do: gettext("Sort by Date")
  defp sort_option_label(:title), do: gettext("Sort by Title")
  defp sort_option_label(:distance), do: gettext("Sort by Distance")
  defp sort_option_label(_), do: gettext("Sort")

  # Private Components

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="animate-pulse space-y-6">
      <div class="h-6 w-48 bg-gray-200 rounded"></div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <%= for _i <- 1..4 do %>
          <div class="bg-white rounded-lg shadow overflow-hidden">
            <div class="h-48 bg-gray-200"></div>
            <div class="p-4 space-y-3">
              <div class="h-5 bg-gray-200 rounded w-3/4"></div>
              <div class="flex items-center space-x-2">
                <div class="h-4 w-4 bg-gray-300 rounded"></div>
                <div class="h-4 bg-gray-200 rounded w-1/2"></div>
              </div>
              <div class="flex items-center space-x-2">
                <div class="h-4 w-4 bg-gray-300 rounded"></div>
                <div class="h-4 bg-gray-200 rounded w-2/3"></div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Flat list display for when date filters are active
  defp flat_event_list(assigns) do
    # Combine all tiers into a flat list (they're already sorted by date)
    all_events =
      assigns.events.short_term ++
        assigns.events.near_term ++
        assigns.events.future

    has_events = length(all_events) > 0
    visible_count = Map.get(assigns.visible_counts, :short_term, 9)
    visible_events = Enum.take(all_events, visible_count)
    remaining_count = length(all_events) - visible_count
    has_more = remaining_count > 0

    assigns =
      assigns
      |> assign(:all_events, all_events)
      |> assign(:has_events, has_events)
      |> assign(:visible_events, visible_events)
      |> assign(:remaining_count, remaining_count)
      |> assign(:has_more, has_more)
      |> assign(:total_count, length(all_events))

    ~H"""
    <div class="space-y-6 mt-6">
      <%= if not @has_events do %>
        <.empty_state message={@empty_message} />
      <% else %>
        <div class="flex items-center justify-between mb-4">
          <p class="text-gray-600">
            <%= @total_count %> <%= ngettext("event", "events", @total_count) %> found
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <%= for item <- @visible_events do %>
            <.render_event_item item={item} language={@language} show_city={@show_city} />
          <% end %>
        </div>

        <%= if @has_more do %>
          <div class="text-center mt-6">
            <button
              type="button"
              phx-click="load_more"
              phx-value-tier="short_term"
              phx-target={@myself}
              class="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 border border-indigo-600 hover:border-indigo-800 rounded-lg transition-colors"
            >
              Load More (<%= @remaining_count %> remaining)
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp event_tiers(assigns) do
    short_term_events = assigns.events.short_term
    near_term_events = assigns.events.near_term
    future_events = assigns.events.future
    past_events = assigns.past_events

    has_short_term = length(short_term_events) > 0
    has_near_term = length(near_term_events) > 0
    has_future = length(future_events) > 0
    has_past = length(past_events) > 0
    has_any_events = has_short_term or has_near_term or has_future
    # Also consider past events if showing them
    has_any_to_show =
      has_any_events or (assigns.show_past_events and has_past)

    assigns =
      assigns
      |> assign(:short_term_events, short_term_events)
      |> assign(:near_term_events, near_term_events)
      |> assign(:future_events, future_events)
      |> assign(:has_short_term, has_short_term)
      |> assign(:has_near_term, has_near_term)
      |> assign(:has_future, has_future)
      |> assign(:has_past, has_past)
      |> assign(:has_any_events, has_any_events)
      |> assign(:has_any_to_show, has_any_to_show)

    ~H"""
    <div class="space-y-8">
      <%= if not @has_any_to_show do %>
        <.empty_state message={@empty_message} />
      <% else %>
        <%!-- Past Events Section (shown at top when toggled) --%>
        <%= if @show_past_toggle and @show_past_events and @has_past do %>
          <div class="border-b border-gray-200 pb-8">
            <.tier_section
              tier={:past}
              events={@past_events}
              tier_config={@tier_config}
              language={@language}
              show_city={@show_city}
              visible_count={Map.get(@visible_counts, :past, 9)}
              myself={@myself}
              collapsed={false}
              is_past={true}
            />
          </div>
        <% end %>

        <!-- Short Term (This Week) -->
        <%= if @has_short_term do %>
          <.tier_section
            tier={:short_term}
            events={@short_term_events}
            tier_config={@tier_config}
            language={@language}
            show_city={@show_city}
            visible_count={Map.get(@visible_counts, :short_term, 9)}
            myself={@myself}
            collapsed={false}
          />
        <% end %>

        <!-- Near Term (This Month) -->
        <%= if @has_near_term do %>
          <.tier_section
            tier={:near_term}
            events={@near_term_events}
            tier_config={@tier_config}
            language={@language}
            show_city={@show_city}
            visible_count={Map.get(@visible_counts, :near_term, 9)}
            myself={@myself}
            collapsed={false}
          />
        <% end %>

        <!-- Future Events (Collapsible) -->
        <%= if @has_future do %>
          <div class="border-t border-gray-200 pt-8">
            <button
              type="button"
              phx-click="toggle_future"
              phx-target={@myself}
              class="flex items-center justify-between w-full text-left group"
            >
              <div>
                <h2 class="text-xl font-semibold text-gray-900 group-hover:text-indigo-600 transition-colors">
                  <%= get_tier_label(@tier_config, :future) %>
                </h2>
                <p class="text-sm text-gray-500">
                  30+ days away · <%= length(@future_events) %> <%= ngettext("event", "events", length(@future_events)) %>
                </p>
              </div>
              <Heroicons.chevron_down class={"w-5 h-5 text-gray-500 transform transition-transform #{if @show_future, do: "rotate-180", else: ""}"} />
            </button>

            <%= if @show_future do %>
              <div class="mt-6">
                <.tier_section
                  tier={:future}
                  events={@future_events}
                  tier_config={@tier_config}
                  language={@language}
                  show_city={@show_city}
                  visible_count={Map.get(@visible_counts, :future, 9)}
                  myself={@myself}
                  collapsed={false}
                  show_header={false}
                />
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  attr :tier, :atom, required: true
  attr :events, :list, required: true
  attr :tier_config, :list, required: true
  attr :language, :string, required: true
  attr :show_city, :boolean, required: true
  attr :visible_count, :integer, required: true
  attr :myself, :any, required: true
  attr :collapsed, :boolean, default: false
  attr :show_header, :boolean, default: true
  attr :is_past, :boolean, default: false

  defp tier_section(assigns) do
    visible_events = Enum.take(assigns.events, assigns.visible_count)
    remaining_count = length(assigns.events) - assigns.visible_count
    has_more = remaining_count > 0

    assigns =
      assigns
      |> assign(:visible_events, visible_events)
      |> assign(:remaining_count, remaining_count)
      |> assign(:has_more, has_more)
      |> assign(:total_count, length(assigns.events))
      |> assign_new(:is_past, fn -> false end)

    ~H"""
    <div>
      <%= if @show_header do %>
        <h2 class="text-2xl font-bold text-gray-900 mb-2">
          <%= get_tier_label(@tier_config, @tier) %>
        </h2>
        <p class="text-gray-600 mb-6">
          <%= get_tier_subtitle(@tier) %>
          <%= if @total_count > 0 do %>
            <span class="text-gray-500">
              · <%= @total_count %> <%= ngettext("event", "events", @total_count) %>
            </span>
          <% end %>
        </p>
      <% end %>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <%= for item <- @visible_events do %>
          <div class={cond do
            @is_past -> "opacity-75 grayscale-[20%]"
            @tier == :future -> "opacity-90"
            true -> ""
          end}>
            <.render_event_item item={item} language={@language} show_city={@show_city} />
          </div>
        <% end %>
      </div>

      <%= if @has_more do %>
        <div class="text-center mt-6">
          <button
            type="button"
            phx-click="load_more"
            phx-value-tier={@tier}
            phx-target={@myself}
            class="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 border border-indigo-600 hover:border-indigo-800 rounded-lg transition-colors"
          >
            Load More (<%= @remaining_count %> remaining)
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="bg-gray-50 rounded-lg p-8 text-center">
      <Heroicons.calendar class="w-12 h-12 text-gray-400 mx-auto mb-3" />
      <p class="text-gray-600"><%= @message %></p>
    </div>
    """
  end

  defp render_event_item(assigns) do
    ~H"""
    <%= cond do %>
      <% match?(%AggregatedMovieGroup{}, @item) -> %>
        <.aggregated_movie_card group={@item} language={@language} show_city={@show_city} />
      <% match?(%AggregatedContainerGroup{}, @item) -> %>
        <.aggregated_container_card group={@item} language={@language} show_city={@show_city} />
      <% is_aggregated?(@item) -> %>
        <.aggregated_event_card group={@item} language={@language} show_city={@show_city} />
      <% true -> %>
        <.event_card event={@item} language={@language} show_city={@show_city} />
    <% end %>
    """
  end

  # Private Helpers

  defp constraint_changed?(socket, new_constraint) do
    Map.get(socket.assigns, :constraint) != new_constraint
  end

  defp filters_changed?(socket, new_filters) do
    Map.get(socket.assigns, :filters) != new_filters
  end

  defp fetch_and_tier_events(socket) do
    constraint = socket.assigns.constraint
    enable_aggregation = socket.assigns.enable_aggregation
    filters = Map.get(socket.assigns, :filters, %{})
    show_past_events = socket.assigns.show_past_events

    # Build query options based on constraint type
    query_opts = build_query_opts(constraint, enable_aggregation, filters)

    # Fetch upcoming events
    events =
      if enable_aggregation do
        PublicEventsEnhanced.list_events_with_aggregation(query_opts)
      else
        PublicEventsEnhanced.list_events(query_opts)
      end

    # Add cover images
    events_with_images =
      Enum.map(events, fn event ->
        Map.put(event, :cover_image_url, PublicEventsEnhanced.get_cover_image_url(event))
      end)

    # Tier the events
    tiered = tier_events(events_with_images, socket.assigns.tier_config)

    # Fetch past events if toggle is enabled or just get the count
    {past_events, past_count} =
      fetch_past_events(constraint, enable_aggregation, show_past_events)

    socket
    |> assign(:events, tiered)
    |> assign(:total_count, length(events))
    |> assign(:past_events, past_events)
    |> assign(:past_count, past_count)
  end

  # Fetch past events - either full list if showing, or just count
  defp fetch_past_events(constraint, enable_aggregation, show_past_events) do
    # Build past events query opts
    past_opts =
      %{
        show_past: true,
        past_only: true,
        sort_by: :starts_at,
        sort_order: :desc,
        page_size: if(show_past_events, do: 100, else: 1),
        aggregate: enable_aggregation
      }
      |> apply_constraint(constraint)

    past_events =
      if enable_aggregation do
        PublicEventsEnhanced.list_events_with_aggregation(past_opts)
      else
        PublicEventsEnhanced.list_events(past_opts)
      end

    # Get count (use a count query for efficiency when not showing)
    past_count =
      if show_past_events do
        length(past_events)
      else
        # Get count from query - for now just use length of limited results
        # This gives an approximation; we could add a dedicated count query
        count_opts =
          %{show_past: true, past_only: true, page_size: 500}
          |> apply_constraint(constraint)

        past_list = PublicEventsEnhanced.list_events(count_opts)
        length(past_list)
      end

    # Add cover images to past events if showing
    past_events_with_images =
      if show_past_events do
        Enum.map(past_events, fn event ->
          Map.put(event, :cover_image_url, PublicEventsEnhanced.get_cover_image_url(event))
        end)
      else
        []
      end

    {past_events_with_images, past_count}
  end

  defp build_query_opts(constraint, enable_aggregation, filters) do
    # Check if we have date filters active - if so, use show_past: true
    # so we respect the exact date range specified
    has_date_filter = Map.has_key?(filters, :start_date) and not is_nil(filters[:start_date])

    # Get sort options from filters or use defaults
    sort_by = Map.get(filters, :sort_by, :starts_at)
    sort_order = Map.get(filters, :sort_order, :asc)

    base_opts = %{
      show_past: has_date_filter,
      sort_by: sort_by,
      sort_order: sort_order,
      page_size: 500,
      aggregate: enable_aggregation
    }

    base_opts
    |> apply_constraint(constraint)
    |> apply_date_filters(filters)
    |> apply_search_filter(filters)
  end

  # Apply search filter if present
  defp apply_search_filter(opts, %{search: search}) when is_binary(search) and search != "" do
    Map.put(opts, :search, search)
  end

  defp apply_search_filter(opts, _filters), do: opts

  # Apply date filters from the filters map if present
  defp apply_date_filters(opts, filters) do
    opts
    |> maybe_put(:start_date, filters[:start_date])
    |> maybe_put(:end_date, filters[:end_date])
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Map.put(opts, key, value)

  defp apply_constraint(opts, {:venue_id, venue_id}) do
    Map.put(opts, :venue_ids, [venue_id])
  end

  defp apply_constraint(opts, {:performer_id, performer_id}) do
    Map.put(opts, :performer_id, performer_id)
  end

  defp apply_constraint(opts, {:city_id, city_id}) do
    Map.put(opts, :city_id, city_id)
  end

  defp apply_constraint(opts, {:radius, %{lat: lat, lng: lng, km: km}}) do
    opts
    |> Map.put(:center_lat, lat)
    |> Map.put(:center_lng, lng)
    |> Map.put(:radius_km, km)
  end

  defp apply_constraint(opts, :global) do
    opts
  end

  defp apply_constraint(opts, nil) do
    opts
  end

  defp tier_events(events, tier_config) do
    now = DateTime.utc_now()

    # Get tier boundaries from config
    short_term_days = get_tier_days(tier_config, :short_term) || 7
    near_term_days = get_tier_days(tier_config, :near_term) || 30

    short_term_boundary = DateTime.add(now, short_term_days, :day)
    near_term_boundary = DateTime.add(now, near_term_days, :day)

    Enum.reduce(events, %{short_term: [], near_term: [], future: []}, fn event, acc ->
      starts_at = get_event_start_date(event)

      cond do
        is_nil(starts_at) ->
          # Events without dates go to future
          %{acc | future: [event | acc.future]}

        DateTime.compare(starts_at, short_term_boundary) == :lt ->
          %{acc | short_term: [event | acc.short_term]}

        DateTime.compare(starts_at, near_term_boundary) == :lt ->
          %{acc | near_term: [event | acc.near_term]}

        true ->
          %{acc | future: [event | acc.future]}
      end
    end)
    |> Map.update!(:short_term, &Enum.reverse/1)
    |> Map.update!(:near_term, &Enum.reverse/1)
    |> Map.update!(:future, &Enum.reverse/1)
  end

  # AggregatedMovieGroup doesn't have a date - show in short_term (most relevant)
  defp get_event_start_date(%AggregatedMovieGroup{}) do
    # Return "now" so movies appear in the short_term tier
    DateTime.utc_now()
  end

  # AggregatedContainerGroup uses start_date (not starts_at)
  defp get_event_start_date(%AggregatedContainerGroup{start_date: start_date}) do
    start_date
  end

  defp get_event_start_date(%{starts_at: starts_at}) do
    starts_at
  end

  defp get_event_start_date(_), do: nil

  defp get_tier_days(tier_config, tier_key) do
    Enum.find_value(tier_config, fn config ->
      if config.key == tier_key, do: config.days
    end)
  end

  defp get_tier_subtitle(:short_term), do: gettext("Next 7 days")
  defp get_tier_subtitle(:near_term), do: gettext("Next 30 days")
  defp get_tier_subtitle(:future), do: gettext("30+ days away")
  defp get_tier_subtitle(:past), do: gettext("Already happened")
  defp get_tier_subtitle(_), do: ""

  # Handle :past tier label separately since it's not in tier_config
  defp get_tier_label(_tier_config, :past), do: gettext("Past Events")

  defp get_tier_label(tier_config, tier_key) do
    Enum.find_value(tier_config, fn config ->
      if config.key == tier_key, do: config.label
    end) || to_string(tier_key)
  end
end
