defmodule EventasaurusWeb.AggregatedContentLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.AggregationTypeSlug
  alias EventasaurusWeb.Helpers.CategoryHelpers
  alias EventasaurusWeb.Helpers.CurrencyHelpers
  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.JsonLd.ItemListSchema
  alias Eventasaurus.CDN

  # Multi-city route: /social/:identifier, /movies/:identifier, etc.
  # Content type is extracted from the URL path (first segment)
  # City will be determined from query params in handle_params
  @impl true
  def mount(%{"identifier" => identifier} = params, _session, socket)
      when not is_map_key(params, "city_slug") do
    # Multi-city route - city will come from query params
    # Use a default city temporarily (will be updated in handle_params)
    # Fallback chain: krakow -> first discovery-enabled city -> error
    default_city =
      Locations.get_city_by_slug("krakow") || Locations.get_first_discovery_enabled_city()

    case default_city do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "No cities available")
         |> push_navigate(to: ~p"/activities")}

      city ->
        # Content type will be extracted from URL path in handle_params
        {:ok,
         socket
         |> assign(:city, city)
         |> assign(:content_type, nil)
         |> assign(:content_type_slug, nil)
         |> assign(:identifier, identifier)
         |> assign(:scope, :all_cities)
         |> assign(:page_title, nil)
         |> assign(:source_name, get_source_name(identifier))
         |> assign(:is_multi_city_route, true)}
    end
  end

  # City-scoped route: /c/:city_slug/:content_type/:identifier
  @impl true
  def mount(
        %{"city_slug" => city_slug, "content_type" => content_type, "identifier" => identifier},
        _session,
        socket
      ) do
    # Convert URL slug to schema.org type for internal use
    schema_type = AggregationTypeSlug.from_slug(content_type)

    # Look up city
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/activities")}

      city ->
        {:ok,
         socket
         |> assign(:city, city)
         |> assign(:content_type, schema_type)
         |> assign(:content_type_slug, content_type)
         |> assign(:identifier, identifier)
         |> assign(:scope, :city_only)
         |> assign(:page_title, format_page_title(schema_type, identifier, city))
         |> assign(:source_name, get_source_name(identifier))
         |> assign(:is_multi_city_route, false)}
    end
  end

  @impl true
  def handle_params(params, url, socket) do
    # Extract content type from URL path for multi-city routes
    # URL format: /social/:identifier or /movies/:identifier, etc.
    socket =
      if socket.assigns[:is_multi_city_route] && is_nil(socket.assigns[:content_type]) do
        content_type_slug = extract_content_type_from_url(url)
        schema_type = AggregationTypeSlug.from_slug(content_type_slug)

        socket
        |> assign(:content_type, schema_type)
        |> assign(:content_type_slug, content_type_slug)
      else
        socket
      end

    # Update city if we're on multi-city route and city param is provided
    socket =
      if socket.assigns[:is_multi_city_route] && params["city"] do
        case Locations.get_city_by_slug(params["city"]) do
          # Keep current city if lookup fails
          nil -> socket
          city -> assign(socket, :city, city)
        end
      else
        socket
      end

    # Determine scope based on route and params
    scope =
      cond do
        # Multi-city route defaults to :all_cities unless explicitly set to city
        socket.assigns[:is_multi_city_route] && params["scope"] != "city" -> :all_cities
        # City-scoped route: check scope param
        params["scope"] == "all" -> :all_cities
        # Default to city_only for city-scoped routes
        true -> :city_only
      end

    socket = load_events(socket, scope)

    {:noreply, socket}
  end

  # Extract content type slug from URL path
  # e.g., "/social/pubquiz-pl?city=krakow" -> "social"
  defp extract_content_type_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> String.split("/", trim: true)
    |> List.first()
  end

  @impl true
  def handle_event("toggle_scope", %{"scope" => scope_str}, socket) do
    scope =
      case scope_str do
        "all_cities" -> :all_cities
        _ -> :city_only
      end

    # Navigate to appropriate route based on scope
    socket =
      socket
      |> assign(:scope, scope)
      |> then(fn socket ->
        if scope == :all_cities do
          # Expanding to all cities - use multi-city route
          # Using string interpolation since routes are now explicit per content type
          push_navigate(socket,
            to:
              "/#{socket.assigns.content_type_slug}/#{socket.assigns.identifier}?scope=all&city=#{socket.assigns.city.slug}"
          )
        else
          # Collapsing to city only - use city-scoped route
          push_navigate(socket,
            to:
              ~p"/c/#{socket.assigns.city.slug}/#{socket.assigns.content_type_slug}/#{socket.assigns.identifier}"
          )
        end
      end)

    {:noreply, socket}
  end

  # Load events based on scope
  defp load_events(socket, scope) do
    city = socket.assigns.city
    content_type = socket.assigns.content_type
    identifier = socket.assigns.identifier

    # Guard against nil city
    if is_nil(city) do
      socket
      |> put_flash(:error, "City not found")
      |> push_navigate(to: ~p"/activities")
    else
      # Fetch all events (no city filter) to count out-of-city events
      all_events = fetch_all_aggregated_events(content_type, identifier)

      # Fetch city-scoped events
      city_events = fetch_aggregated_events(content_type, identifier, city)

      # Count events outside current city
      out_of_city_count = length(all_events) - length(city_events)

      # Get unique cities from all events (safely handle missing venue/city data)
      unique_cities =
        all_events
        |> Enum.map(fn event ->
          event.venue && event.venue.city_id
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()

      # TOTAL event count is ALWAYS all events across all cities
      total_event_count = length(all_events)

      # Group events based on scope
      {venue_groups, city_groups} =
        case scope do
          :all_cities ->
            # Group by city, then by venue within each city
            groups = group_events_by_city(all_events, city)
            {[], groups}

          :city_only ->
            # Group by venue only for current city
            venue_groups =
              city_events
              |> Enum.group_by(& &1.venue_id)
              |> Enum.map(fn {_venue_id, venue_events} ->
                %{event: List.first(venue_events)}
              end)
              |> Enum.sort_by(& &1.event.venue.name)

            {venue_groups, []}
        end

      # Extract hero image from first event with an image
      hero_image =
        (venue_groups ++ Enum.flat_map(city_groups, & &1.venue_groups))
        |> Enum.find_value(fn %{event: event} ->
          Map.get(event, :cover_image_url)
        end)

      # Build breadcrumb items using standard helper
      breadcrumb_items =
        BreadcrumbBuilder.build_aggregated_source_breadcrumbs(
          city,
          content_type,
          socket.assigns.source_name,
          scope
        )

      # Update page title after city is finalized
      page_title = format_page_title(content_type, identifier, city)

      # Get all events for the current scope for JSON-LD
      events_for_schema = if scope == :all_cities, do: all_events, else: city_events

      # Generate JSON-LD structured data
      json_ld =
        ItemListSchema.generate(events_for_schema, content_type, identifier, city, max_items: 20)

      # Generate Open Graph meta tags
      og_tags =
        build_aggregation_open_graph(
          content_type,
          identifier,
          city,
          total_event_count,
          hero_image
        )

      socket
      |> assign(:scope, scope)
      |> assign(:page_title, page_title)
      |> assign(:venue_schedules, venue_groups)
      |> assign(:city_groups, city_groups)
      |> assign(:out_of_city_count, out_of_city_count)
      |> assign(:unique_cities, unique_cities)
      |> assign(:total_event_count, total_event_count)
      |> assign(:hero_image, hero_image)
      |> assign(:breadcrumb_items, breadcrumb_items)
      |> assign(:json_ld, json_ld)
      |> assign(:open_graph, og_tags)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Hero Section with Background Image -->
      <%= if @hero_image do %>
        <div class="relative h-64 md:h-80 bg-gray-900">
          <img
            src={@hero_image}
            alt={@source_name}
            class="absolute inset-0 w-full h-full object-cover opacity-60"
          />
          <div class="absolute inset-0 bg-gradient-to-t from-gray-900/80 to-transparent"></div>

          <div class="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-full flex flex-col justify-end pb-8">
            <!-- Breadcrumbs -->
            <Breadcrumbs.breadcrumb
              items={@breadcrumb_items}
              text_color="text-white/80 hover:text-white"
            />

            <h1 class="text-4xl md:text-5xl font-bold text-white">
              <%= @source_name %> in <%= @city.name %>
            </h1>

            <div class="mt-4 flex flex-wrap items-center gap-3 text-gray-200">
              <!-- Multi-city badge -->
              <%= if @out_of_city_count > 0 do %>
                <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-500/90 text-white">
                  <Heroicons.map_pin class="w-4 h-4 mr-1" />
                  Multi-city
                </span>
              <% end %>

              <!-- Location count -->
              <div class="flex items-center">
                <Heroicons.building_storefront class="w-5 h-5 mr-2" />
                <span>
                  <%= if @scope == :all_cities do %>
                    <%= @total_event_count %> <%= ngettext("location", "locations", @total_event_count) %> across <%= @unique_cities %> <%= ngettext("city", "cities", @unique_cities) %>
                  <% else %>
                    <%= length(@venue_schedules) %> <%= ngettext("location", "locations", length(@venue_schedules)) %> in <%= @city.name %>
                  <% end %>
                </span>
              </div>
            </div>

            <!-- Expansion button (city scope only, if out-of-city events exist) -->
            <%= if @scope == :city_only && @out_of_city_count > 0 do %>
              <div class="mt-6">
                <button
                  phx-click="toggle_scope"
                  phx-value-scope="all_cities"
                  class="inline-flex items-center px-4 py-2 bg-white/90 hover:bg-white text-gray-900 font-medium rounded-lg transition-colors shadow-lg hover:shadow-xl"
                >
                  <Heroicons.arrow_top_right_on_square class="w-5 h-5 mr-2" />
                  View all <%= @total_event_count %> events in <%= @unique_cities %> <%= ngettext("city", "cities", @unique_cities) %>
                </button>
              </div>
            <% end %>

            <!-- Collapse button (all cities scope) -->
            <%= if @scope == :all_cities do %>
              <div class="mt-6">
                <button
                  phx-click="toggle_scope"
                  phx-value-scope="city_only"
                  class="inline-flex items-center px-4 py-2 bg-white/20 hover:bg-white/30 text-white font-medium rounded-lg transition-colors border border-white/30"
                >
                  <Heroicons.arrow_uturn_left class="w-5 h-5 mr-2" />
                  Show only <%= @city.name %>
                </button>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <!-- Fallback: White header without image -->
        <div class="bg-white shadow-sm border-b">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <!-- Breadcrumbs -->
            <Breadcrumbs.breadcrumb items={@breadcrumb_items} class="mb-4" />

            <h1 class="text-4xl font-bold text-gray-900">
              <%= @source_name %> in <%= @city.name %>
            </h1>

            <div class="mt-4 flex flex-wrap items-center gap-3 text-gray-600">
              <!-- Multi-city badge -->
              <%= if @out_of_city_count > 0 do %>
                <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-500 text-white">
                  <Heroicons.map_pin class="w-4 h-4 mr-1" />
                  Multi-city
                </span>
              <% end %>

              <!-- Location count -->
              <div class="flex items-center">
                <Heroicons.building_storefront class="w-5 h-5 mr-2" />
                <span>
                  <%= if @scope == :all_cities do %>
                    <%= @total_event_count %> <%= ngettext("location", "locations", @total_event_count) %> across <%= @unique_cities %> <%= ngettext("city", "cities", @unique_cities) %>
                  <% else %>
                    <%= length(@venue_schedules) %> <%= ngettext("location", "locations", length(@venue_schedules)) %> in <%= @city.name %>
                  <% end %>
                </span>
              </div>
            </div>

            <!-- Expansion button (city scope only, if out-of-city events exist) -->
            <%= if @scope == :city_only && @out_of_city_count > 0 do %>
              <div class="mt-6">
                <button
                  phx-click="toggle_scope"
                  phx-value-scope="all_cities"
                  class="inline-flex items-center px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white font-medium rounded-lg transition-colors shadow-sm hover:shadow-md"
                >
                  <Heroicons.arrow_top_right_on_square class="w-5 h-5 mr-2" />
                  View all <%= @total_event_count %> events in <%= @unique_cities %> <%= ngettext("city", "cities", @unique_cities) %>
                </button>
              </div>
            <% end %>

            <!-- Collapse button (all cities scope) -->
            <%= if @scope == :all_cities do %>
              <div class="mt-6">
                <button
                  phx-click="toggle_scope"
                  phx-value-scope="city_only"
                  class="inline-flex items-center px-4 py-2 bg-gray-200 hover:bg-gray-300 text-gray-900 font-medium rounded-lg transition-colors"
                >
                  <Heroicons.arrow_uturn_left class="w-5 h-5 mr-2" />
                  Show only <%= @city.name %>
                </button>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Event Display: City-Scoped or City-Grouped -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= if @scope == :city_only do %>
          <!-- City-Scoped: Venue Grid -->
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for schedule <- @venue_schedules do %>
              <.event_card event={schedule.event} />
            <% end %>
          </div>
        <% else %>
          <!-- Multi-City: City-Grouped Display -->
          <%= for city_group <- @city_groups do %>
            <div class="mb-12">
              <!-- City Header -->
              <div class="flex items-center justify-between mb-6 pb-4 border-b-2 border-gray-200">
                <div class="flex items-center gap-3">
                  <h2 class="text-2xl font-bold text-gray-900">
                    <.link
                      navigate={"/#{@content_type_slug}/#{@identifier}?scope=all&city=#{city_group.city.slug}"}
                      class="hover:text-blue-600 transition-colors"
                    >
                      <%= city_group.city.name %>
                    </.link>
                  </h2>
                  <%= if city_group.is_current do %>
                    <span class="px-2 py-1 rounded text-sm font-medium bg-green-100 text-green-800">
                      Current City
                    </span>
                  <% end %>
                </div>
                <div class="flex items-center gap-4 text-sm text-gray-600">
                  <%= if city_group.distance_km && !city_group.is_current do %>
                    <div class="flex items-center">
                      <Heroicons.arrow_long_right class="w-4 h-4 mr-1" />
                      <span><%= city_group.distance_km %> km away</span>
                    </div>
                  <% end %>
                  <div class="flex items-center">
                    <Heroicons.building_storefront class="w-4 h-4 mr-1" />
                    <span><%= city_group.event_count %> <%= ngettext("location", "locations", city_group.event_count) %></span>
                  </div>
                </div>
              </div>

              <!-- Venue Grid for this City -->
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                <%= for schedule <- city_group.venue_groups do %>
                  <.event_card event={schedule.event} />
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

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
          <!-- Time-Sensitive Badge -->
          <%= if badge = PublicEventsEnhanced.get_time_sensitive_badge(@event) do %>
            <div class={[
              "absolute top-3 right-3 text-white px-2 py-1 rounded-md text-xs font-medium",
              case badge.type do
                :last_chance -> "bg-red-500"
                :this_week -> "bg-orange-500"
                :upcoming -> "bg-blue-500"
                _ -> "bg-gray-500"
              end
            ]}>
              <%= badge.label %>
            </div>
          <% end %>
          <!-- Recurring Event Badge -->
          <%= if PublicEvent.recurring?(@event) do %>
            <div class="absolute bottom-3 right-3 bg-green-500 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center">
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
                <%= PublicEvent.frequency_label(@event) %> • Next: <%= format_datetime_with_tz(PublicEvent.next_occurrence_date(@event), @event) %>
              </span>
            <% else %>
              <%= format_datetime_with_tz(@event.starts_at, @event) %>
            <% end %>
          </div>
          <%= if @event.venue do %>
            <div class="mt-1 flex items-center text-sm text-gray-600">
              <Heroicons.map_pin class="w-4 h-4 mr-1" />
              <%= @event.venue.name %>
            </div>
          <% end %>
          <%= if has_pricing?(@event) do %>
            <div class="mt-2">
              <span class="text-sm font-medium text-gray-900">
                <%= format_price_range(@event) %>
              </span>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # Fetch events for a specific content type + identifier in a city
  defp fetch_aggregated_events(_content_type, identifier, city) do
    # For now, we'll use source slug as the identifier for trivia
    # In the future, this could handle movies by title, classes by name, etc.
    source_slug = identifier

    # Get city coordinates for radius filtering
    lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
    lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

    # Query events by source slug with geographic radius filtering (matching CityLive.Index)
    # This ensures we show all events within the city's radius, not just exact city matches
    PublicEventsEnhanced.list_events(%{
      source_slug: source_slug,
      center_lat: lat,
      center_lng: lng,
      # Same default as CityLive.Index
      radius_km: 50,
      include_pattern_events: true,
      # Get all results (max limit)
      page_size: 500,
      # NEW: Pass browsing city for Unsplash fallback images
      browsing_city_id: city.id
    })
  end

  # Fetch ALL events for this source across all cities (no geographic filter)
  defp fetch_all_aggregated_events(_content_type, identifier) do
    source_slug = identifier

    events =
      PublicEventsEnhanced.list_events(%{
        source_slug: source_slug,
        include_pattern_events: true,
        # Get all results (max limit)
        page_size: 500
      })

    # Preload venue.city_ref association for distance calculations and city grouping
    EventasaurusApp.Repo.preload(events, venue: :city_ref)
  end

  # Group events by city with distance calculations
  defp group_events_by_city(events, current_city) when is_list(events) do
    current_lat = if current_city.latitude, do: Decimal.to_float(current_city.latitude), else: nil

    current_lng =
      if current_city.longitude, do: Decimal.to_float(current_city.longitude), else: nil

    events
    # Filter out events without venue or city
    |> Enum.filter(fn event ->
      event.venue && event.venue.city_id
    end)
    |> Enum.group_by(fn event ->
      event.venue.city_id
    end)
    |> Enum.map(fn {city_id, city_events} ->
      # Get city info from first event's venue (we know venue.city_ref is preloaded)
      city = List.first(city_events).venue.city_ref

      # Calculate distance from current city
      distance_km =
        if current_lat && current_lng && city.latitude && city.longitude do
          calculate_distance(
            current_lat,
            current_lng,
            Decimal.to_float(city.latitude),
            Decimal.to_float(city.longitude)
          )
        else
          nil
        end

      # Group by venue within this city
      venue_groups =
        city_events
        |> Enum.group_by(& &1.venue_id)
        |> Enum.map(fn {_venue_id, venue_events} ->
          %{event: List.first(venue_events)}
        end)
        |> Enum.sort_by(& &1.event.venue.name)

      %{
        city: city,
        city_id: city_id,
        distance_km: distance_km,
        event_count: length(city_events),
        venue_groups: venue_groups,
        # Is this the current city?
        is_current: city_id == current_city.id
      }
    end)
    |> Enum.sort_by(fn group ->
      # Sort: current city first, then by distance
      if group.is_current, do: {0, 0}, else: {1, group.distance_km || 999_999}
    end)
  end

  # Handle empty list case
  defp group_events_by_city([], _current_city), do: []

  # Calculate distance between two points using Haversine formula
  # Returns distance in kilometers
  defp calculate_distance(lat1, lon1, lat2, lon2) do
    # Earth's radius in kilometers
    r = 6371.0

    # Convert to radians
    lat1_rad = lat1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    delta_lat = (lat2 - lat1) * :math.pi() / 180
    delta_lon = (lon2 - lon1) * :math.pi() / 180

    # Haversine formula
    a =
      :math.sin(delta_lat / 2) * :math.sin(delta_lat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(delta_lon / 2) * :math.sin(delta_lon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    distance = r * c

    Float.round(distance, 1)
  end

  # NEW: Format datetime with timezone conversion
  # Extracts timezone from event.occurrences and converts UTC to local time
  defp format_datetime_with_tz(%DateTime{} = datetime, event) do
    # Extract timezone from occurrences (pattern events have timezone info)
    timezone = extract_timezone_from_event(event)

    # Convert UTC to local timezone
    local_datetime =
      case DateTime.shift_zone(datetime, timezone) do
        {:ok, local_dt} -> local_dt
        {:error, _} -> datetime
      end

    Calendar.strftime(local_datetime, "%b %d at %I:%M %p")
    |> String.replace(" 0", " ")
  end

  defp format_datetime_with_tz(%NaiveDateTime{} = datetime, _event) do
    Calendar.strftime(datetime, "%b %d at %I:%M %p")
    |> String.replace(" 0", " ")
  end

  defp format_datetime_with_tz(_, _), do: "Date TBD"

  # Extract timezone from event occurrences
  # For pattern events: occurrences.pattern.timezone (e.g., "America/Denver")
  # For explicit events: Fallback to UTC
  defp extract_timezone_from_event(%{occurrences: %{"pattern" => %{"timezone" => tz}}})
       when is_binary(tz) and tz != "" do
    tz
  end

  defp extract_timezone_from_event(_event), do: "Etc/UTC"

  defp format_page_title(content_type, identifier, city) do
    source_name = get_source_name(identifier)
    "#{source_name} #{String.capitalize(content_type)} in #{city.name}"
  end

  defp get_source_name(slug), do: Source.get_display_name(slug)

  # Check if event has pricing information (from first source)
  defp has_pricing?(event) do
    case event.sources do
      [source | _] -> source.min_price || source.max_price
      _ -> false
    end
  end

  # Format price range with currency support using CurrencyHelpers
  defp format_price_range(event) do
    # Get pricing from first source
    source = List.first(event.sources)

    if source do
      currency_symbol = CurrencyHelpers.currency_symbol(source.currency || "USD")

      cond do
        source.min_price && source.max_price && Decimal.equal?(source.min_price, source.max_price) ->
          "#{currency_symbol}#{source.min_price}"

        source.min_price && source.max_price ->
          "#{currency_symbol}#{source.min_price} - #{currency_symbol}#{source.max_price}"

        source.min_price ->
          "From #{currency_symbol}#{source.min_price}"

        source.max_price ->
          "Up to #{currency_symbol}#{source.max_price}"

        true ->
          "Price not available"
      end
    else
      "Price not available"
    end
  end

  # Build Open Graph meta tags for aggregation pages
  defp build_aggregation_open_graph(content_type, identifier, city, total_event_count, hero_image) do
    base_url = EventasaurusWeb.Layouts.get_base_url()

    # Convert identifier to title case
    identifier_name =
      identifier
      |> String.replace("-", " ")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")

    # Convert schema type to friendly name
    type_name = schema_type_to_friendly_name(content_type)

    # Build title and description
    title = "#{identifier_name} - #{type_name} in #{city.name}"

    description =
      "Discover #{String.replace(identifier, "-", " ")} and other #{type_name} in #{city.name}. #{total_event_count} #{pluralize("event", total_event_count)} available."

    # Use hero image or generate placeholder
    image_url =
      if hero_image do
        hero_image
      else
        identifier_encoded = URI.encode(identifier_name)
        "https://placehold.co/1200x630/4ECDC4/FFFFFF?text=#{identifier_encoded}"
      end

    # Wrap with CDN
    cdn_image_url = CDN.url(image_url)

    # Build canonical URL
    content_type_slug = EventasaurusDiscovery.AggregationTypeSlug.to_slug(content_type)
    canonical_url = "#{base_url}/c/#{city.slug}/#{content_type_slug}/#{identifier}"

    # Generate Open Graph tags
    Phoenix.HTML.Safe.to_iodata(
      EventasaurusWeb.Components.OpenGraphComponent.open_graph_tags(%{
        type: "website",
        title: title,
        description: description,
        image_url: cdn_image_url,
        image_width: 1200,
        image_height: 630,
        url: canonical_url,
        site_name: "Wombie",
        locale: "en_US",
        twitter_card: "summary_large_image"
      })
    )
    |> IO.iodata_to_binary()
  end

  # Convert schema.org type to friendly name
  defp schema_type_to_friendly_name(schema_type) do
    case schema_type do
      "SocialEvent" -> "social events"
      "FoodEvent" -> "food events"
      "MusicEvent" -> "music events"
      "ComedyEvent" -> "comedy shows"
      "DanceEvent" -> "dance performances"
      "EducationEvent" -> "classes and workshops"
      "SportsEvent" -> "sports events"
      "TheaterEvent" -> "theater performances"
      "Festival" -> "festivals"
      "ScreeningEvent" -> "movie screenings"
      _ -> "events"
    end
  end

  # Helper for pluralization
  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"
end
