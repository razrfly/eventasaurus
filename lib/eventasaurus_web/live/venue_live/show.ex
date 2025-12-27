defmodule EventasaurusWeb.VenueLive.Show do
  use EventasaurusWeb, :live_view

  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.PublicEvents
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusWeb.Components.OpenGraphComponent
  alias EventasaurusWeb.Components.Activity.VenueHeroCard
  alias EventasaurusWeb.Components.Activity.VenueLocationCard
  alias EventasaurusWeb.Components.Activity.ActivityLayout
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.FollowButtonComponent
  alias EventasaurusWeb.Helpers.{BreadcrumbBuilder, LanguageDiscovery, SEOHelpers}
  alias EventasaurusWeb.JsonLd.LocalBusinessSchema
  alias EventasaurusWeb.JsonLd.BreadcrumbListSchema
  alias EventasaurusWeb.UrlHelper
  alias EventasaurusWeb.Live.Helpers.EventFilters
  alias EventasaurusWeb.Live.Helpers.EventPagination
  alias EventasaurusDiscovery.Pagination

  import Ecto.Query
  import EventasaurusWeb.Components.EventListing

  # Maximum events to load for client-side filtering
  # Configurable via application config: :eventasaurus_web, :max_venue_events
  @max_venue_events Application.compile_env(:eventasaurus_web, :max_venue_events, 5000)

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

    # Get language from session params (if present) or default to English
    params = get_connect_params(socket) || %{}
    language = params["locale"] || "en"

    socket =
      socket
      |> assign(:venue, nil)
      |> assign(:loading, true)
      |> assign(:language, language)
      |> assign(:available_languages, ["en"])
      |> assign(:request_uri, request_uri)
      # Unified event list with filtering (replaces separate upcoming/future/past)
      |> assign(:events, [])
      |> assign(:all_events, [])
      |> assign(:total_events, 0)
      |> assign(:all_events_count, 0)
      # Date filtering - nil means show all events (paginated)
      |> assign(:active_date_range, nil)
      |> assign(:date_range_counts, %{})
      |> assign(:filters, %{search: nil})
      # Sorting
      |> assign(:sort_by, :starts_at)
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
      # Legacy assigns (kept for backward compatibility with sidebar)
      |> assign(:nearby_events, [])
      |> assign(:show_past_events, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(
        %{"venue_slug" => venue_slug, "city_slug" => city_slug} = params,
        _url,
        socket
      ) do
    # City-scoped venue route (e.g., /c/:city_slug/venues/:venue_slug)
    venue = get_venue_by_slug(venue_slug, city_slug)

    case venue do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Venue not found"))
         |> push_navigate(to: ~p"/")}

      venue ->
        # Apply URL params to socket assigns, then load venue
        # Track that we're using the city-scoped route pattern
        socket =
          socket
          |> apply_url_params(params)
          |> assign(:route_pattern, :city_scoped)

        load_and_assign_venue(venue, socket)
    end
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _url, socket) do
    # Direct venue slug route (e.g., /venues/:slug)
    venue = get_venue_by_slug(slug, params["city_slug"])

    case venue do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Venue not found"))
         |> push_navigate(to: ~p"/")}

      venue ->
        # Apply URL params to socket assigns, then load venue
        # Track that we're using the direct route pattern
        socket =
          socket
          |> apply_url_params(params)
          |> assign(:route_pattern, :direct)

        load_and_assign_venue(venue, socket)
    end
  end

  # Quick date filter handler
  @impl true
  def handle_event("quick_date_filter", %{"range" => range_string}, socket) do
    case EventFilters.parse_quick_range(range_string) do
      {:ok, range_atom} ->
        active_date_range = if range_atom == :all, do: nil, else: range_atom

        # Filter events by the selected date range, preserving search and sort
        all_events = socket.assigns.all_events
        search_term = socket.assigns.filters[:search]
        sort_by = socket.assigns.sort_by

        {paginated_events, pagination, filtered_count} =
          EventPagination.filter_and_paginate(all_events,
            date_range: active_date_range,
            search: search_term,
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

        # Update URL with new filter state
        {:noreply, push_patch(socket, to: build_path(socket))}

      :error ->
        {:noreply, socket}
    end
  end

  # Clear date filter handler
  @impl true
  def handle_event("clear_date_filter", _params, socket) do
    # Reset to default (all events), preserving search and sort
    active_date_range = nil
    all_events = socket.assigns.all_events
    search_term = socket.assigns.filters[:search]
    sort_by = socket.assigns.sort_by

    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        date_range: active_date_range,
        search: search_term,
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

    # Update URL with cleared filter state
    {:noreply, push_patch(socket, to: build_path(socket))}
  end

  # Pagination handler
  @impl true
  def handle_event("paginate", %{"page" => page_string}, socket) do
    page = String.to_integer(page_string)
    all_events = socket.assigns.all_events
    active_date_range = socket.assigns.active_date_range
    search_term = socket.assigns.filters[:search]
    sort_by = socket.assigns.sort_by

    {paginated_events, pagination, _filtered_count} =
      EventPagination.filter_and_paginate(all_events,
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
    active_date_range = socket.assigns.active_date_range
    sort_by = socket.assigns.sort_by

    # Filter by date range, search term, and sort
    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
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

  # Sort handler
  @impl true
  def handle_event("sort", %{"sort_by" => sort_by_string}, socket) do
    sort_by = parse_sort(sort_by_string)
    all_events = socket.assigns.all_events
    active_date_range = socket.assigns.active_date_range
    search_term = socket.assigns.filters[:search]

    # Re-filter and sort events with the new sort order
    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
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

    # Update URL with new sort option
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
    active_date_range = socket.assigns.active_date_range
    sort_by = socket.assigns.sort_by

    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
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

  # Handle auth modal request from FollowButtonComponent
  @impl true
  def handle_info({:show_auth_modal, :follow}, socket) do
    # Redirect to login with return URL to come back after authentication
    venue = socket.assigns.venue
    route_pattern = socket.assigns[:route_pattern] || :direct

    return_to =
      case route_pattern do
        :city_scoped -> ~p"/c/#{venue.city_ref.slug}/venues/#{venue.slug}"
        :direct -> ~p"/venues/#{venue.slug}"
      end

    {:noreply,
     socket
     |> put_flash(:info, gettext("Please log in to follow this venue"))
     |> redirect(to: ~p"/auth/login?return_to=#{return_to}")}
  end

  # Helper functions

  # Shared logic for loading and assigning venue data to socket
  defp load_and_assign_venue(venue, socket) do
    # Preload city and country (images come from cached_images table)
    venue = Repo.preload(venue, city_ref: :country)

    # Get all upcoming events for this venue (for filtering)
    all_events = get_all_venue_events(venue.id)
    all_events_count = length(all_events)

    # Calculate date range counts for quick filters
    date_range_counts = EventPagination.calculate_date_range_counts(all_events)

    # Apply filters (date range, search, sort) and paginate
    active_date_range = socket.assigns.active_date_range
    search_term = socket.assigns.filters[:search]
    sort_by = socket.assigns.sort_by
    page_size = socket.assigns.pagination.page_size
    page_number = socket.assigns.pagination.page_number

    {paginated_events, pagination, filtered_count} =
      EventPagination.filter_and_paginate(all_events,
        date_range: active_date_range,
        search: search_term,
        sort_by: sort_by,
        page: page_number,
        page_size: page_size
      )

    # Get nearby events in the same city (excluding events at this venue)
    nearby_events =
      if venue.city_id do
        get_nearby_city_events(venue.city_id, venue.id, limit: 6)
      else
        []
      end

    # Build breadcrumb items with city hierarchy using BreadcrumbBuilder
    breadcrumb_items = BreadcrumbBuilder.build_venue_breadcrumbs(venue)

    # Get available languages for this venue's city (dynamic based on country + DB translations)
    available_languages =
      if venue.city_ref && venue.city_ref.slug do
        LanguageDiscovery.get_available_languages_for_city(venue.city_ref.slug)
      else
        ["en"]
      end

    # Determine language based on session locale (already set in mount) or default
    language = socket.assigns.language

    # Generate JSON-LD structured data
    json_ld_schemas =
      generate_json_ld_schemas(venue, breadcrumb_items, socket.assigns.request_uri)

    # Build venue description for SEO (using total event count)
    description = build_venue_description_simple(venue, all_events_count)

    # Build canonical path
    canonical_path =
      if venue.city_ref do
        "/c/#{venue.city_ref.slug}/venues/#{venue.slug}"
      else
        "/venues/#{venue.slug}"
      end

    # Generate Open Graph meta tags with branded social card
    og_tags =
      build_venue_open_graph(
        venue,
        description,
        canonical_path,
        socket.assigns.request_uri,
        all_events_count
      )

    socket =
      socket
      |> assign(:venue, venue)
      |> assign(:all_events, all_events)
      |> assign(:events, paginated_events)
      |> assign(:total_events, filtered_count)
      |> assign(:all_events_count, all_events_count)
      |> assign(:date_range_counts, date_range_counts)
      |> assign(:pagination, pagination)
      |> assign(:nearby_events, nearby_events)
      |> assign(:breadcrumb_items, breadcrumb_items)
      |> assign(:available_languages, available_languages)
      |> assign(:language, language)
      |> assign(:loading, false)
      |> assign(:open_graph, og_tags)
      |> SEOHelpers.assign_meta_tags(
        title: venue.name,
        description: description,
        type: "website",
        canonical_path: canonical_path,
        json_ld: json_ld_schemas,
        request_uri: socket.assigns.request_uri
      )

    {:noreply, socket}
  end

  defp get_venue_by_slug(slug, city_slug) when is_binary(city_slug) do
    # City-scoped lookup - preload city_ref for URL building
    from(v in Venue,
      join: c in assoc(v, :city_ref),
      where: v.slug == ^slug and c.slug == ^city_slug,
      preload: [:city_ref],
      limit: 1
    )
    |> Repo.one()
  end

  defp get_venue_by_slug(slug, _city_slug) do
    # Direct slug lookup - preload city_ref for URL building
    from(v in Venue,
      where: v.slug == ^slug,
      preload: [:city_ref],
      limit: 1
    )
    |> Repo.one()
  end

  # Get all upcoming events for a venue (for filtering)
  defp get_all_venue_events(venue_id) do
    PublicEvents.by_venue(venue_id,
      upcoming_only: true,
      limit: @max_venue_events,
      preload: [:performers, :categories, :sources]
    )
    |> Enum.map(fn event ->
      Map.put(event, :cover_image_url, PublicEventsEnhanced.get_cover_image_url(event))
    end)
    |> Enum.sort_by(& &1.starts_at, DateTime)
  end

  # Build venue description for SEO (simplified version)
  defp build_venue_description_simple(venue, event_count) do
    city_name = if venue.city_ref, do: venue.city_ref.name, else: nil

    cond do
      city_name && venue.address ->
        "#{venue.name} located at #{venue.address}, #{city_name}. " <>
          "Discover #{event_count} upcoming events and activities."

      city_name ->
        "#{venue.name} in #{city_name}. " <>
          "Discover #{event_count} upcoming events and activities."

      venue.address ->
        "#{venue.name} located at #{venue.address}. " <>
          "Discover #{event_count} upcoming events and activities."

      true ->
        "#{venue.name} - Discover #{event_count} upcoming events and activities."
    end
  end

  defp get_nearby_city_events(city_id, current_venue_id, opts) do
    alias EventasaurusDiscovery.PublicEvents.PublicEvent

    limit = Keyword.get(opts, :limit, 6)
    now = DateTime.utc_now()

    # Get upcoming events from other venues in the same city (excluding current venue)
    from(pe in PublicEvent,
      join: v in Venue,
      on: pe.venue_id == v.id,
      where: v.city_id == ^city_id,
      where: pe.venue_id != ^current_venue_id,
      where:
        (not is_nil(pe.ends_at) and pe.ends_at > ^now) or
          (is_nil(pe.ends_at) and pe.starts_at > ^now),
      order_by: [asc: pe.starts_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload([:performers, :categories, :sources, venue: [city_ref: :country]])
    |> Enum.map(fn event ->
      Map.put(event, :cover_image_url, PublicEventsEnhanced.get_cover_image_url(event))
    end)
  end

  # Generate combined JSON-LD schemas for venue page
  defp generate_json_ld_schemas(venue, breadcrumb_items, request_uri) do
    base_url = get_base_url_from_request(request_uri)

    # 1. LocalBusiness schema for the venue (with request_uri for canonical URLs)
    local_business_json = LocalBusinessSchema.generate(venue, request_uri: request_uri)

    # 2. BreadcrumbList schema for navigation
    breadcrumb_list_json =
      BreadcrumbListSchema.from_breadcrumb_builder_items(
        breadcrumb_items,
        build_venue_url(venue, base_url),
        base_url
      )

    # Combine schemas into a JSON-LD array
    # Parse both JSON strings, combine into array, re-encode
    with {:ok, business_schema} <- Jason.decode(local_business_json),
         {:ok, breadcrumb_schema} <- Jason.decode(breadcrumb_list_json) do
      # Return as JSON array of schemas
      Jason.encode!([business_schema, breadcrumb_schema])
    else
      _ ->
        # Fallback: return just the business schema if parsing fails
        local_business_json
    end
  end

  # Build full venue URL using request_uri for ngrok support
  defp build_venue_url(venue, base_url) do
    path =
      if venue.city_ref do
        "/c/#{venue.city_ref.slug}/venues/#{venue.slug}"
      else
        "/venues/#{venue.slug}"
      end

    "#{base_url}#{path}"
  end

  # Build Open Graph meta tags for venue pages with branded social card
  defp build_venue_open_graph(venue, description, canonical_path, request_uri, event_count) do
    # Build absolute canonical URL using UrlHelper to avoid double slash issues
    canonical_url = UrlHelper.build_url(canonical_path, request_uri)

    # Get cover image for the social card data
    cover_image_url =
      case Venue.get_cover_image(venue, width: 800, height: 419, quality: 85) do
        {:ok, url, _source} -> url
        {:error, :no_image} -> nil
      end

    # Build venue data for social card hash generation
    venue_data = %{
      name: venue.name,
      slug: venue.slug,
      city_ref: %{
        name: if(venue.city_ref, do: venue.city_ref.name, else: ""),
        slug: if(venue.city_ref, do: venue.city_ref.slug, else: "")
      },
      address: venue.address,
      event_count: event_count,
      cover_image_url: cover_image_url,
      updated_at: venue.updated_at
    }

    # Generate branded social card URL path
    social_card_path = HashGenerator.generate_url_path(venue_data, :venue)

    # Build absolute image URL
    social_card_url = UrlHelper.build_url(social_card_path, request_uri)

    # Generate Open Graph tags with branded social card
    Phoenix.HTML.Safe.to_iodata(
      OpenGraphComponent.open_graph_tags(%{
        type: "place",
        title: "#{venue.name} · Wombie",
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

  # Get base URL from request_uri or fallback to config
  defp get_base_url_from_request(nil), do: UrlHelper.get_base_url()

  defp get_base_url_from_request(%URI{} = uri) do
    scheme = uri.scheme || "https"
    host = uri.host || UrlHelper.get_base_url()

    port_string =
      case uri.port do
        nil -> ""
        80 when scheme == "http" -> ""
        443 when scheme == "https" -> ""
        port -> ":#{port}"
      end

    "#{scheme}://#{host}#{port_string}"
  end

  # URL State Management Functions

  # Apply URL params to socket assigns for initial load or navigation
  defp apply_url_params(socket, params) do
    # Parse page from URL
    page = parse_integer(params["page"]) || 1

    # Parse search from URL
    search = params["search"]

    # Parse sort from URL
    sort_by = parse_sort(params["sort"])

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

    # Update socket assigns with URL params
    socket
    |> assign(:filters, %{search: search})
    |> assign(:sort_by, sort_by)
    |> assign(:active_date_range, active_date_range)
    |> assign(:pagination, %Pagination{
      entries: [],
      page_number: page,
      page_size: socket.assigns.pagination.page_size,
      total_entries: 0,
      total_pages: 0
    })
  end

  # Build URL path with current filter state
  # IMPORTANT: Must stay within the same live_session to use push_patch
  # - :city_scoped routes are in live_session :city (/c/:city_slug/venues/:venue_slug)
  # - :direct routes are in live_session :default (/venues/:slug)
  defp build_path(socket) do
    venue = socket.assigns.venue
    params = build_filter_params(socket)
    route_pattern = socket.assigns[:route_pattern] || :direct

    # Use the same route pattern we came in with to stay in the same live_session
    base_path =
      case route_pattern do
        :city_scoped ->
          ~p"/c/#{venue.city_ref.slug}/venues/#{venue.slug}"

        :direct ->
          ~p"/venues/#{venue.slug}"
      end

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

    # Add sort if not default (starts_at)
    params =
      case socket.assigns.sort_by do
        :starts_at -> params
        sort_by -> Map.put(params, "sort", Atom.to_string(sort_by))
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

  # Parse sort field from string
  defp parse_sort(nil), do: :starts_at
  defp parse_sort("title"), do: :title
  defp parse_sort("starts_at"), do: :starts_at
  defp parse_sort("popularity"), do: :popularity
  # Distance removed - unclear UX ("distance from what?")
  defp parse_sort("distance"), do: :starts_at
  defp parse_sort(_), do: :starts_at

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <%= if @loading do %>
        <.loading_skeleton />
      <% else %>
        <!-- Hero Section -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <!-- Breadcrumb -->
          <nav class="mb-4">
            <Breadcrumbs.breadcrumb items={@breadcrumb_items} />
          </nav>

          <!-- Venue Hero Card -->
          <VenueHeroCard.venue_hero_card
            venue={@venue}
            upcoming_event_count={@all_events_count}
          >
            <:actions>
              <.live_component
                module={FollowButtonComponent}
                id={"follow-venue-#{@venue.id}"}
                entity={@venue}
                entity_type={:venue}
                current_user={@user}
              />
            </:actions>
          </VenueHeroCard.venue_hero_card>
        </div>

        <!-- Main Content with Two-Column Layout -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <ActivityLayout.activity_layout>
            <:main>
              <!-- Events Section with Filters -->
              <div class="space-y-6">
                <!-- Header with View Mode Toggle and Sort -->
                <div class="flex items-center justify-between">
                  <h2 class="text-2xl font-bold text-gray-900">
                    <%= gettext("Events") %>
                  </h2>
                  <div class="flex items-center gap-4">
                    <.sort_controls sort_by={@sort_by} show_popularity={true} />
                    <.view_toggle view_mode={@view_mode} />
                  </div>
                </div>

                <!-- Search Bar -->
                <.search_bar filters={@filters} />

                <!-- Quick Date Filters -->
                <.quick_date_filters
                  active_date_range={@active_date_range}
                  date_range_counts={@date_range_counts}
                  all_events_count={@all_events_count}
                />

                <!-- Active Filter Tags -->
                <.simple_filter_tags
                  filters={@filters}
                  active_date_range={@active_date_range}
                  sort_by={@sort_by}
                />

                <!-- Event Results -->
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
              </div>
            </:main>

            <:sidebar>
              <!-- Location Map Card -->
              <VenueLocationCard.venue_location_card
                venue={@venue}
                map_id="venue-location-map"
              />

              <!-- Nearby Events -->
              <%= if !Enum.empty?(@nearby_events) && @venue.city_ref do %>
                <div class="bg-white rounded-xl border border-gray-200 p-5">
                  <h3 class="text-lg font-semibold text-gray-900 mb-4">
                    <span class="flex items-center gap-2">
                      <Heroicons.sparkles class="w-5 h-5 text-indigo-500" />
                      <%= gettext("More in %{city}", city: @venue.city_ref.name) %>
                    </span>
                  </h3>
                  <div class="space-y-4">
                    <%= for event <- Enum.take(@nearby_events, 3) do %>
                      <.link navigate={~p"/activities/#{event.slug}"} class="block group">
                        <div class="flex gap-3">
                          <%= if Map.get(event, :cover_image_url) do %>
                            <div class="flex-shrink-0 w-16 h-16 rounded-lg overflow-hidden bg-gray-100">
                              <img
                                src={Map.get(event, :cover_image_url)}
                                alt=""
                                class="w-full h-full object-cover"
                                loading="lazy"
                              />
                            </div>
                          <% else %>
                            <div class="flex-shrink-0 w-16 h-16 rounded-lg bg-gray-100 flex items-center justify-center">
                              <Heroicons.calendar class="w-6 h-6 text-gray-400" />
                            </div>
                          <% end %>
                          <div class="min-w-0 flex-1">
                            <p class="font-medium text-gray-900 group-hover:text-indigo-600 transition-colors line-clamp-2 text-sm">
                              <%= event.display_title || event.title %>
                            </p>
                            <p class="text-xs text-gray-500 mt-1">
                              <%= if event.starts_at do %>
                                <%= Calendar.strftime(event.starts_at, "%b %d") %>
                              <% end %>
                              <%= if event.venue do %>
                                · <%= event.venue.name %>
                              <% end %>
                            </p>
                          </div>
                        </div>
                      </.link>
                    <% end %>
                  </div>
                  <%= if length(@nearby_events) > 3 do %>
                    <.link
                      navigate={~p"/c/#{@venue.city_ref.slug}"}
                      class="mt-4 block text-center text-sm font-medium text-indigo-600 hover:text-indigo-800 transition-colors"
                    >
                      <%= gettext("View all events in %{city}", city: @venue.city_ref.name) %> →
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </:sidebar>
          </ActivityLayout.activity_layout>
        </div>
      <% end %>
    </div>
    """
  end
end
