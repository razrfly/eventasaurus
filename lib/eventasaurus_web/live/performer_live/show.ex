defmodule EventasaurusWeb.PerformerLive.Show do
  @moduledoc """
  LiveView for displaying performer/artist detail pages.

  Shows performer information using the PerformerHeroCard component
  and displays upcoming/past events using EventCards for consistency
  with city and venue pages.

  Uses ActivityLayout for consistent two-column responsive layout
  matching venue and activity pages.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Performers.PerformerStore
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusWeb.Live.Helpers.EventFilters
  alias EventasaurusWeb.Live.Helpers.EventPagination

  alias EventasaurusWeb.Components.Breadcrumbs

  alias EventasaurusWeb.Components.Activity.{
    ActivityLayout,
    ClickableStatsCard,
    PerformerHeroCard
  }

  alias EventasaurusWeb.Helpers.BreadcrumbBuilder

  import EventasaurusWeb.Components.EventListing

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:performer, nil)
      |> assign(:loading, true)
      |> assign(:stats, %{})
      # Unified event list with filtering (all events: upcoming + past)
      |> assign(:events, [])
      |> assign(:all_events, [])
      |> assign(:total_events, 0)
      # Time filter - :upcoming (default), :past, or :all
      |> assign(:time_filter, :upcoming)
      |> assign(:time_filter_counts, %{upcoming: 0, past: 0, all: 0})
      # Date filtering - nil means show all events (paginated)
      |> assign(:active_date_range, nil)
      |> assign(:date_range_counts, %{})
      |> assign(:filters, %{search: nil})
      # Pagination
      |> assign(:pagination, %Pagination{
        entries: [],
        page_number: 1,
        page_size: 30,
        total_entries: 0,
        total_pages: 0
      })
      # View mode
      |> assign(:view_mode, "grid")
      |> assign(:breadcrumb_items, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _url, socket) do
    case PerformerStore.get_performer_by_slug(slug) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Performer not found"))
         |> push_navigate(to: ~p"/")}

      performer ->
        load_and_assign_performer(performer, socket)
    end
  end

  defp load_and_assign_performer(performer, socket) do
    # Get stats and events
    stats = PerformerStore.get_performer_stats(performer.id)
    events = PerformerStore.get_performer_events(performer.id)

    # Combine all events (upcoming + past) for unified filtering
    all_events = events.upcoming ++ events.past

    # Calculate time filter counts (upcoming, past, all)
    time_filter_counts = EventPagination.calculate_time_filter_counts(all_events)

    # Apply default time filter (:upcoming) and get filtered events
    time_filter = socket.assigns.time_filter
    time_filtered_events = EventPagination.filter_by_time(all_events, time_filter)

    # Calculate date range counts for the time-filtered events
    date_range_counts = EventPagination.calculate_date_range_counts(time_filtered_events)

    # Apply date range filter and paginate
    active_date_range = socket.assigns.active_date_range
    filtered_events = EventPagination.filter_by_date_range(time_filtered_events, active_date_range)
    page_size = socket.assigns.pagination.page_size
    page_number = socket.assigns.pagination.page_number
    {paginated_events, pagination} = EventPagination.paginate(filtered_events, page_number, page_size)

    # Build breadcrumb items
    breadcrumb_items =
      BreadcrumbBuilder.build_performer_breadcrumbs(performer,
        gettext_backend: EventasaurusWeb.Gettext
      )

    socket =
      socket
      |> assign(:performer, performer)
      |> assign(:stats, stats)
      |> assign(:all_events, all_events)
      |> assign(:events, paginated_events)
      |> assign(:total_events, length(filtered_events))
      |> assign(:time_filter_counts, time_filter_counts)
      |> assign(:date_range_counts, date_range_counts)
      |> assign(:pagination, pagination)
      |> assign(:loading, false)
      |> assign(:page_title, performer.name)
      |> assign(:breadcrumb_items, breadcrumb_items)

    {:noreply, socket}
  end

  # Time filter handler (sidebar stats clicks)
  @impl true
  def handle_event("time_filter", %{"filter" => filter_string}, socket) do
    time_filter = String.to_existing_atom(filter_string)
    all_events = socket.assigns.all_events

    # Apply time filter
    time_filtered_events = EventPagination.filter_by_time(all_events, time_filter)

    # Recalculate date range counts for the new time filter
    date_range_counts = EventPagination.calculate_date_range_counts(time_filtered_events)

    # Reset to page 1 and clear date range filter when switching time filter
    page_size = socket.assigns.pagination.page_size
    {paginated_events, pagination} = EventPagination.paginate(time_filtered_events, 1, page_size)

    {:noreply,
     socket
     |> assign(:time_filter, time_filter)
     |> assign(:active_date_range, nil)
     |> assign(:date_range_counts, date_range_counts)
     |> assign(:events, paginated_events)
     |> assign(:total_events, length(time_filtered_events))
     |> assign(:pagination, pagination)}
  end

  # Quick date filter handler
  @impl true
  def handle_event("quick_date_filter", %{"range" => range_string}, socket) do
    case EventFilters.parse_quick_range(range_string) do
      {:ok, range_atom} ->
        active_date_range = if range_atom == :all, do: nil, else: range_atom

        all_events = socket.assigns.all_events
        time_filter = socket.assigns.time_filter

        # Apply time filter first, then date range
        time_filtered = EventPagination.filter_by_time(all_events, time_filter)
        filtered_events = EventPagination.filter_by_date_range(time_filtered, active_date_range)

        page_size = socket.assigns.pagination.page_size
        {paginated_events, pagination} = EventPagination.paginate(filtered_events, 1, page_size)

        {:noreply,
         socket
         |> assign(:active_date_range, active_date_range)
         |> assign(:events, paginated_events)
         |> assign(:total_events, length(filtered_events))
         |> assign(:pagination, pagination)}

      :error ->
        {:noreply, socket}
    end
  end

  # Clear date filter handler
  @impl true
  def handle_event("clear_date_filter", _params, socket) do
    # Reset date range but keep time filter
    active_date_range = nil
    all_events = socket.assigns.all_events
    time_filter = socket.assigns.time_filter

    time_filtered = EventPagination.filter_by_time(all_events, time_filter)
    filtered_events = EventPagination.filter_by_date_range(time_filtered, active_date_range)

    page_size = socket.assigns.pagination.page_size
    {paginated_events, pagination} = EventPagination.paginate(filtered_events, 1, page_size)

    {:noreply,
     socket
     |> assign(:active_date_range, active_date_range)
     |> assign(:events, paginated_events)
     |> assign(:total_events, length(filtered_events))
     |> assign(:pagination, pagination)}
  end

  # Pagination handler
  @impl true
  def handle_event("paginate", %{"page" => page_string}, socket) do
    page = String.to_integer(page_string)
    all_events = socket.assigns.all_events
    time_filter = socket.assigns.time_filter
    active_date_range = socket.assigns.active_date_range

    time_filtered = EventPagination.filter_by_time(all_events, time_filter)
    filtered_events = EventPagination.filter_by_date_range(time_filtered, active_date_range)

    page_size = socket.assigns.pagination.page_size
    {paginated_events, pagination} = EventPagination.paginate(filtered_events, page, page_size)

    {:noreply,
     socket
     |> assign(:events, paginated_events)
     |> assign(:pagination, pagination)}
  end

  # Search handler
  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    all_events = socket.assigns.all_events
    time_filter = socket.assigns.time_filter
    active_date_range = socket.assigns.active_date_range

    # Filter by time, date range and search term, then paginate
    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        time_filter: time_filter,
        date_range: active_date_range,
        search: search_term,
        page: 1,
        page_size: socket.assigns.pagination.page_size
      )

    {:noreply,
     socket
     |> assign(:filters, %{search: search_term})
     |> assign(:events, paginated_events)
     |> assign(:total_events, filtered_count)
     |> assign(:pagination, pagination)}
  end

  # View mode toggle handler
  @impl true
  def handle_event("change_view", %{"view" => view_mode}, socket) do
    {:noreply, assign(socket, :view_mode, view_mode)}
  end

  # Helper to get section title based on active time filter
  defp events_section_title(:upcoming), do: gettext("Upcoming Events")
  defp events_section_title(:past), do: gettext("Past Events")
  defp events_section_title(:all), do: gettext("All Events")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <%= if @loading do %>
        <.loading_skeleton />
      <% else %>
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <!-- Breadcrumbs -->
          <Breadcrumbs.breadcrumb items={@breadcrumb_items} class="mb-6" />

          <ActivityLayout.activity_layout>
            <:main>
              <!-- Performer Hero Card -->
              <PerformerHeroCard.performer_hero_card
                performer={@performer}
                upcoming_event_count={@time_filter_counts.upcoming}
                total_event_count={@stats.total_events}
              />

              <!-- Events Section -->
              <div>
                <h2 class="text-2xl font-bold text-gray-900 mb-6">
                  <%= events_section_title(@time_filter) %>
                </h2>

                <!-- Search and Filters -->
                <div class="mb-6 space-y-4">
                  <.search_bar filters={@filters} />
                  <%= if @time_filter != :past do %>
                    <.quick_date_filters
                      active_date_range={@active_date_range}
                      date_range_counts={@date_range_counts}
                      all_events_count={@time_filter_counts[@time_filter]}
                    />
                  <% end %>
                </div>

                <%= if Enum.empty?(@events) do %>
                  <.empty_state message={gettext("No events found matching your filters")} />
                <% else %>
                  <.event_results
                    events={@events}
                    view_mode={@view_mode}
                    language="en"
                    total_events={@total_events}
                    show_city={true}
                  />

                  <%= if @pagination.total_pages > 1 do %>
                    <.pagination pagination={@pagination} />
                  <% end %>
                <% end %>
              </div>
            </:main>

            <:sidebar>
              <!-- Performer Stats Card (Clickable Filters) -->
              <ClickableStatsCard.clickable_stats_card title={gettext("Artist Stats")}>
                <:stat
                  label={gettext("Upcoming Events")}
                  count={@time_filter_counts.upcoming}
                  filter_value={:upcoming}
                  active={@time_filter == :upcoming}
                />
                <:stat
                  label={gettext("Past Events")}
                  count={@time_filter_counts.past}
                  filter_value={:past}
                  active={@time_filter == :past}
                />
                <:stat
                  label={gettext("All Events")}
                  count={@time_filter_counts.all}
                  filter_value={:all}
                  active={@time_filter == :all}
                />
              </ClickableStatsCard.clickable_stats_card>

              <!-- External Links Card (if RA URL exists) -->
              <%= if get_ra_url(@performer) do %>
                <div class="bg-white rounded-lg shadow-md p-6">
                  <h3 class="text-lg font-semibold text-gray-900 mb-4">
                    <%= gettext("External Links") %>
                  </h3>
                  <a
                    href={get_ra_url(@performer)}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center text-indigo-600 hover:text-indigo-800 font-medium"
                  >
                    <Heroicons.arrow_top_right_on_square class="w-5 h-5 mr-2" />
                    <%= gettext("Resident Advisor") %>
                  </a>
                </div>
              <% end %>
            </:sidebar>
          </ActivityLayout.activity_layout>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper to extract RA URL from performer metadata
  defp get_ra_url(%{metadata: %{"ra_artist_url" => url}}) when is_binary(url), do: url
  defp get_ra_url(_), do: nil
end
