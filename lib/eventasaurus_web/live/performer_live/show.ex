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

  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusDiscovery.Performers.PerformerStore
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusWeb.Components.OpenGraphComponent
  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.Live.Helpers.EventFilters
  alias EventasaurusWeb.Live.Helpers.EventPagination
  alias EventasaurusWeb.UrlHelper

  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.FollowButtonComponent

  alias EventasaurusWeb.Components.Activity.{
    ActivityLayout,
    ClickableStatsCard,
    PerformerHeroCard
  }

  alias EventasaurusWeb.Helpers.BreadcrumbBuilder

  import EventasaurusWeb.Components.EventListing

  @impl true
  def mount(_params, _session, socket) do
    # CRITICAL: Capture request URI for correct URL generation (ngrok support)
    raw_uri = get_connect_info(socket, :uri)

    request_uri =
      cond do
        match?(%URI{}, raw_uri) -> raw_uri
        is_binary(raw_uri) -> URI.parse(raw_uri)
        true -> nil
      end

    socket =
      socket
      |> assign(:performer, nil)
      |> assign(:loading, true)
      |> assign(:stats, %{})
      |> assign(:request_uri, request_uri)
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
      # Sorting
      |> assign(:sort_by, :starts_at)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _url, socket) do
    case PerformerStore.get_performer_by_slug(slug) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Performer not found"))
         |> push_navigate(to: ~p"/")}

      performer ->
        # Apply URL params to socket assigns, then load performer
        socket = apply_url_params(socket, params)
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

    # Apply all filters (time, date range, search, sort) and paginate
    active_date_range = socket.assigns.active_date_range
    search_term = socket.assigns.filters[:search]
    sort_by = socket.assigns.sort_by
    page_size = socket.assigns.pagination.page_size
    page_number = socket.assigns.pagination.page_number

    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        time_filter: time_filter,
        date_range: active_date_range,
        search: search_term,
        sort_by: sort_by,
        page: page_number,
        page_size: page_size
      )

    # Build breadcrumb items
    breadcrumb_items =
      BreadcrumbBuilder.build_performer_breadcrumbs(performer,
        gettext_backend: EventasaurusWeb.Gettext
      )

    # Build SEO description
    upcoming_count = time_filter_counts.upcoming
    description = build_performer_description(performer, upcoming_count)

    # Build canonical path
    canonical_path = "/performers/#{performer.slug}"

    # Generate Open Graph tags with branded social card
    og_tags =
      build_performer_open_graph(
        performer,
        description,
        canonical_path,
        socket.assigns.request_uri,
        upcoming_count
      )

    socket =
      socket
      |> assign(:performer, performer)
      |> assign(:stats, stats)
      |> assign(:all_events, all_events)
      |> assign(:events, paginated_events)
      |> assign(:total_events, filtered_count)
      |> assign(:time_filter_counts, time_filter_counts)
      |> assign(:date_range_counts, date_range_counts)
      |> assign(:pagination, pagination)
      |> assign(:loading, false)
      |> assign(:page_title, performer.name)
      |> assign(:breadcrumb_items, breadcrumb_items)
      |> assign(:open_graph, og_tags)
      |> SEOHelpers.assign_meta_tags(
        title: performer.name,
        description: description,
        type: "profile",
        canonical_path: canonical_path,
        request_uri: socket.assigns.request_uri
      )

    {:noreply, socket}
  end

  # Build SEO description for performer
  defp build_performer_description(performer, upcoming_count) do
    base = "#{performer.name}"

    event_info =
      case upcoming_count do
        0 -> "No upcoming events"
        1 -> "1 upcoming event"
        n -> "#{n} upcoming events"
      end

    "#{base} · #{event_info} · Find tickets and showtimes on Wombie"
  end

  # Build Open Graph tags for performer page
  defp build_performer_open_graph(
         performer,
         description,
         canonical_path,
         request_uri,
         event_count
       ) do
    # Build absolute canonical URL
    canonical_url = UrlHelper.build_url(canonical_path, request_uri)

    # Build performer data for social card hash generation
    performer_data = %{
      name: performer.name,
      slug: performer.slug,
      image_url: performer.image_url,
      event_count: event_count,
      updated_at: performer.updated_at
    }

    # Generate branded social card URL path
    social_card_path = HashGenerator.generate_url_path(performer_data, :performer)

    # Build absolute image URL
    social_card_url = UrlHelper.build_url(social_card_path, request_uri)

    # Generate Open Graph tags with branded social card
    Phoenix.HTML.Safe.to_iodata(
      OpenGraphComponent.open_graph_tags(%{
        type: "profile",
        title: "#{performer.name} · Wombie",
        description: description,
        image_url: social_card_url,
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

  # Time filter handler (sidebar stats clicks)
  @impl true
  def handle_event("time_filter", %{"filter" => filter_string}, socket) do
    time_filter = String.to_existing_atom(filter_string)
    all_events = socket.assigns.all_events
    sort_by = socket.assigns.sort_by

    # Apply time filter
    time_filtered_events = EventPagination.filter_by_time(all_events, time_filter)

    # Recalculate date range counts for the new time filter
    date_range_counts = EventPagination.calculate_date_range_counts(time_filtered_events)

    # Reset to page 1 and clear date range filter when switching time filter
    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        time_filter: time_filter,
        date_range: nil,
        sort_by: sort_by,
        page: 1,
        page_size: socket.assigns.pagination.page_size
      )

    socket =
      socket
      |> assign(:time_filter, time_filter)
      |> assign(:active_date_range, nil)
      |> assign(:date_range_counts, date_range_counts)
      |> assign(:events, paginated_events)
      |> assign(:total_events, filtered_count)
      |> assign(:pagination, pagination)

    # Update URL with new time filter
    {:noreply, push_patch(socket, to: build_path(socket))}
  end

  # Quick date filter handler
  @impl true
  def handle_event("quick_date_filter", %{"range" => range_string}, socket) do
    case EventFilters.parse_quick_range(range_string) do
      {:ok, range_atom} ->
        active_date_range = if range_atom == :all, do: nil, else: range_atom

        all_events = socket.assigns.all_events
        time_filter = socket.assigns.time_filter
        sort_by = socket.assigns.sort_by

        {paginated_events, pagination, filtered_count} =
          EventPagination.filter_and_paginate(all_events,
            time_filter: time_filter,
            date_range: active_date_range,
            sort_by: sort_by,
            page: 1,
            page_size: socket.assigns.pagination.page_size
          )

        socket =
          socket
          |> assign(:active_date_range, active_date_range)
          |> assign(:events, paginated_events)
          |> assign(:total_events, filtered_count)
          |> assign(:pagination, pagination)

        # Update URL with new date range
        {:noreply, push_patch(socket, to: build_path(socket))}

      :error ->
        {:noreply, socket}
    end
  end

  # Clear date filter handler
  @impl true
  def handle_event("clear_date_filter", _params, socket) do
    # Reset date range but keep time filter and sort
    all_events = socket.assigns.all_events
    time_filter = socket.assigns.time_filter
    sort_by = socket.assigns.sort_by

    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        time_filter: time_filter,
        date_range: nil,
        sort_by: sort_by,
        page: 1,
        page_size: socket.assigns.pagination.page_size
      )

    socket =
      socket
      |> assign(:active_date_range, nil)
      |> assign(:events, paginated_events)
      |> assign(:total_events, filtered_count)
      |> assign(:pagination, pagination)

    # Update URL with cleared filter state
    {:noreply, push_patch(socket, to: build_path(socket))}
  end

  # Pagination handler
  @impl true
  def handle_event("paginate", %{"page" => page_string}, socket) do
    page = String.to_integer(page_string)
    all_events = socket.assigns.all_events
    time_filter = socket.assigns.time_filter
    active_date_range = socket.assigns.active_date_range
    search_term = socket.assigns.filters[:search]
    sort_by = socket.assigns.sort_by

    {paginated_events, pagination, _filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        time_filter: time_filter,
        date_range: active_date_range,
        search: search_term,
        sort_by: sort_by,
        page: page,
        page_size: socket.assigns.pagination.page_size
      )

    socket =
      socket
      |> assign(:events, paginated_events)
      |> assign(:pagination, pagination)

    # Update URL with new page
    {:noreply, push_patch(socket, to: build_path(socket))}
  end

  # Search handler
  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    all_events = socket.assigns.all_events
    time_filter = socket.assigns.time_filter
    active_date_range = socket.assigns.active_date_range
    sort_by = socket.assigns.sort_by

    # Filter by time, date range, search term and sort, then paginate
    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        time_filter: time_filter,
        date_range: active_date_range,
        search: search_term,
        sort_by: sort_by,
        page: 1,
        page_size: socket.assigns.pagination.page_size
      )

    socket =
      socket
      |> assign(:filters, %{search: search_term})
      |> assign(:events, paginated_events)
      |> assign(:total_events, filtered_count)
      |> assign(:pagination, pagination)

    # Update URL with search term
    {:noreply, push_patch(socket, to: build_path(socket))}
  end

  # View mode toggle handler
  @impl true
  def handle_event("change_view", %{"view" => view_mode}, socket) do
    {:noreply, assign(socket, :view_mode, view_mode)}
  end

  # Clear search handler
  @impl true
  def handle_event("clear_search", _params, socket) do
    all_events = socket.assigns.all_events
    time_filter = socket.assigns.time_filter
    active_date_range = socket.assigns.active_date_range
    sort_by = socket.assigns.sort_by

    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        time_filter: time_filter,
        date_range: active_date_range,
        search: nil,
        sort_by: sort_by,
        page: 1,
        page_size: socket.assigns.pagination.page_size
      )

    socket =
      socket
      |> assign(:filters, %{search: nil})
      |> assign(:events, paginated_events)
      |> assign(:total_events, filtered_count)
      |> assign(:pagination, pagination)

    {:noreply, push_patch(socket, to: build_path(socket))}
  end

  # Sort handler
  @impl true
  def handle_event("sort", %{"sort_by" => sort_by_string}, socket) do
    sort_by = parse_sort(sort_by_string)
    all_events = socket.assigns.all_events
    time_filter = socket.assigns.time_filter
    active_date_range = socket.assigns.active_date_range
    search_term = socket.assigns.filters[:search]

    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        time_filter: time_filter,
        date_range: active_date_range,
        search: search_term,
        sort_by: sort_by,
        page: 1,
        page_size: socket.assigns.pagination.page_size
      )

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:events, paginated_events)
      |> assign(:total_events, filtered_count)
      |> assign(:pagination, pagination)

    {:noreply, push_patch(socket, to: build_path(socket))}
  end

  # Handle auth modal request from FollowButtonComponent
  @impl true
  def handle_info({:show_auth_modal, :follow}, socket) do
    # Redirect to login with return URL to come back after authentication
    performer = socket.assigns.performer
    return_to = ~p"/performers/#{performer.slug}"

    {:noreply,
     socket
     |> put_flash(:info, gettext("Please log in to follow this artist"))
     |> redirect(to: ~p"/auth/login?return_to=#{return_to}")}
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
              >
                <:actions>
                  <.live_component
                    module={FollowButtonComponent}
                    id={"follow-performer-#{@performer.id}"}
                    entity={@performer}
                    entity_type={:performer}
                    current_user={@user}
                  />
                </:actions>
              </PerformerHeroCard.performer_hero_card>

              <!-- Events Section -->
              <div>
                <!-- Header with View Mode Toggle and Sort -->
                <div class="flex items-center justify-between mb-6">
                  <h2 class="text-2xl font-bold text-gray-900">
                    <%= events_section_title(@time_filter) %>
                  </h2>
                  <div class="flex items-center gap-4">
                    <.sort_controls sort_by={@sort_by} show_popularity={true} />
                    <.view_toggle view_mode={@view_mode} />
                  </div>
                </div>

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

                  <!-- Active Filter Tags -->
                  <.simple_filter_tags
                    filters={@filters}
                    active_date_range={@active_date_range}
                    sort_by={@sort_by}
                  />
                </div>

                <%= if Enum.empty?(@events) do %>
                  <.empty_state message={gettext("No events found matching your filters")} />
                <% else %>
                  <.event_results
                    events={@events}
                    view_mode={@view_mode}
                    language="en"
                    pagination={@pagination}
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

  # URL State Management Functions

  # Apply URL params to socket assigns for initial load or navigation
  defp apply_url_params(socket, params) do
    # Parse page from URL
    page = parse_integer(params["page"]) || 1

    # Parse search from URL
    search = params["search"]

    # Parse time filter from URL (upcoming, past, all)
    time_filter =
      case params["time_filter"] do
        "upcoming" -> :upcoming
        "past" -> :past
        "all" -> :all
        # Default to upcoming
        _ -> :upcoming
      end

    # Parse date range from URL
    active_date_range =
      case params["date_range"] do
        nil ->
          nil

        "all" ->
          nil

        range_string ->
          case EventFilters.parse_quick_range(range_string) do
            {:ok, range_atom} -> range_atom
            :error -> nil
          end
      end

    # Parse sort from URL
    sort_by = parse_sort(params["sort"])

    # Update socket assigns with URL params
    socket
    |> assign(:filters, %{search: search})
    |> assign(:time_filter, time_filter)
    |> assign(:active_date_range, active_date_range)
    |> assign(:sort_by, sort_by)
    |> assign(:pagination, %Pagination{
      entries: [],
      page_number: page,
      page_size: socket.assigns.pagination.page_size,
      total_entries: 0,
      total_pages: 0
    })
  end

  # Build URL path with current filter state
  defp build_path(socket) do
    performer = socket.assigns.performer
    params = build_filter_params(socket)

    base_path = ~p"/performers/#{performer.slug}"

    if map_size(params) > 0 do
      "#{base_path}?#{URI.encode_query(params)}"
    else
      base_path
    end
  end

  # Build filter params map for URL query string
  defp build_filter_params(socket) do
    params = %{}

    # Add search if present
    params =
      case socket.assigns.filters[:search] do
        nil -> params
        "" -> params
        search -> Map.put(params, "search", search)
      end

    # Add time filter if not default (upcoming)
    params =
      case socket.assigns.time_filter do
        # Default, don't include in URL
        :upcoming -> params
        time_filter -> Map.put(params, "time_filter", Atom.to_string(time_filter))
      end

    # Add date range if set (not nil means a specific range is selected)
    params =
      case socket.assigns.active_date_range do
        nil -> params
        range -> Map.put(params, "date_range", Atom.to_string(range))
      end

    # Add page if not first page
    params =
      case socket.assigns.pagination.page_number do
        1 -> params
        page -> Map.put(params, "page", to_string(page))
      end

    # Add sort if not default (starts_at)
    params =
      case socket.assigns.sort_by do
        # Default, don't include in URL
        :starts_at -> params
        sort_by -> Map.put(params, "sort", Atom.to_string(sort_by))
      end

    params
  end

  # Parse integer from string, returning nil for invalid input
  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> nil
    end
  end

  # Parse sort option from URL string
  defp parse_sort(nil), do: :starts_at
  defp parse_sort("title"), do: :title
  defp parse_sort("starts_at"), do: :starts_at
  defp parse_sort("popularity"), do: :popularity
  # Distance removed - unclear UX ("distance from what?")
  defp parse_sort("distance"), do: :starts_at
  defp parse_sort(_), do: :starts_at

  # Helper to extract RA URL from performer metadata
  defp get_ra_url(%{metadata: %{"ra_artist_url" => url}}) when is_binary(url), do: url
  defp get_ra_url(_), do: nil
end
