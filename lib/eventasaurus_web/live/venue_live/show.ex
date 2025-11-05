defmodule EventasaurusWeb.VenueLive.Show do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.PublicEvents
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusWeb.VenueLive.Components.ImageGallery
  alias EventasaurusWeb.StaticMapComponent
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.JsonLd.LocalBusinessSchema
  alias EventasaurusWeb.JsonLd.BreadcrumbListSchema
  alias EventasaurusWeb.UrlHelper
  import Ecto.Query
  import EventasaurusWeb.Components.EventCards

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
      |> assign(:request_uri, request_uri)
      |> assign(:upcoming_events, [])
      |> assign(:future_events, [])
      |> assign(:past_events, [])
      |> assign(:show_past_events, false)
      |> assign(:show_future_events, false)
      |> assign(:nearby_events, [])
      |> assign(:upcoming_page_size, 9)
      |> assign(:upcoming_visible_count, 9)
      |> assign(:future_page_size, 9)
      |> assign(:future_visible_count, 9)
      |> assign(:past_page_size, 9)
      |> assign(:past_visible_count, 9)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"venue_slug" => venue_slug, "city_slug" => city_slug} = _params, _url, socket) do
    # City-scoped venue route (e.g., /c/:city_slug/venues/:venue_slug)
    venue = get_venue_by_slug(venue_slug, city_slug)

    case venue do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Venue not found"))
         |> push_navigate(to: ~p"/")}

      venue ->
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
        load_and_assign_venue(venue, socket)
    end
  end

  @impl true
  def handle_event("toggle_past_events", _params, socket) do
    {:noreply, assign(socket, :show_past_events, !socket.assigns.show_past_events)}
  end

  @impl true
  def handle_event("toggle_future_events", _params, socket) do
    {:noreply, assign(socket, :show_future_events, !socket.assigns.show_future_events)}
  end

  @impl true
  def handle_event("load_more_upcoming", _params, socket) do
    new_count = socket.assigns.upcoming_visible_count + socket.assigns.upcoming_page_size
    {:noreply, assign(socket, :upcoming_visible_count, new_count)}
  end

  @impl true
  def handle_event("load_more_future", _params, socket) do
    new_count = socket.assigns.future_visible_count + socket.assigns.future_page_size
    {:noreply, assign(socket, :future_visible_count, new_count)}
  end

  @impl true
  def handle_event("load_more_past", _params, socket) do
    new_count = socket.assigns.past_visible_count + socket.assigns.past_page_size
    {:noreply, assign(socket, :past_visible_count, new_count)}
  end

  # Helper functions

  # Check if venue has any images
  defp has_venue_images?(%Venue{venue_images: images}) when is_list(images) and length(images) > 0, do: true
  defp has_venue_images?(_), do: false

  # Shared logic for loading and assigning venue data to socket
  defp load_and_assign_venue(venue, socket) do
    # Preload city and country
    venue = Repo.preload(venue, city_ref: :country)

    # Get events for this venue
    events = get_venue_events(venue.id)

    # Get nearby events in the same city (excluding events at this venue)
    nearby_events =
      if venue.city_id do
        get_nearby_city_events(venue.city_id, venue.id, limit: 6)
      else
        []
      end

    # Build breadcrumb items with city hierarchy
    breadcrumb_items = build_venue_breadcrumbs(venue)

    # Generate JSON-LD structured data
    json_ld_schemas =
      generate_json_ld_schemas(venue, breadcrumb_items, socket.assigns.request_uri)

    # Build venue description for SEO
    description = build_venue_description(venue, events)

    # Build canonical path
    canonical_path =
      if venue.city_ref do
        "/c/#{venue.city_ref.slug}/venues/#{venue.slug}"
      else
        "/venues/#{venue.slug}"
      end

    socket =
      socket
      |> assign(:venue, venue)
      |> assign(:upcoming_events, events.upcoming)
      |> assign(:future_events, events.future)
      |> assign(:past_events, events.past)
      |> assign(:nearby_events, nearby_events)
      |> assign(:breadcrumb_items, breadcrumb_items)
      |> assign(:loading, false)
      |> SEOHelpers.assign_meta_tags(
        title: "#{venue.name} - Wombie",
        description: description,
        type: "website",
        canonical_path: canonical_path,
        json_ld: json_ld_schemas,
        request_uri: socket.assigns.request_uri
      )

    {:noreply, socket}
  end

  defp get_venue_by_slug(slug, city_slug) when is_binary(city_slug) do
    # City-scoped lookup
    from(v in Venue,
      join: c in assoc(v, :city_ref),
      where: v.slug == ^slug and c.slug == ^city_slug,
      limit: 1
    )
    |> Repo.one()
  end

  defp get_venue_by_slug(slug, _city_slug) do
    # Direct slug lookup
    Repo.get_by(Venue, slug: slug)
  end

  defp get_venue_events(venue_id) do
    now = DateTime.utc_now()
    thirty_days_from_now = DateTime.add(now, 30, :day)

    # Get upcoming events (limit 5000 - venues rarely have this many future events)
    # This ensures we capture all upcoming/future events even for high-volume venues
    # Preload all necessary associations for the shared event card component
    upcoming_events =
      PublicEvents.by_venue(venue_id,
        upcoming_only: true,
        limit: 5000,
        preload: [:performers, :categories, :sources]
      )

    # Get recent past events using a separate query with reverse chronological order
    # We want the MOST RECENT past events, not the oldest ones
    past_events = get_recent_past_events(venue_id, limit: 500)

    # Combine and group all events
    all_events = upcoming_events ++ past_events

    # Add cover_image_url virtual field to events for compatibility with shared event card component
    all_events_with_images =
      Enum.map(all_events, fn event ->
        Map.put(event, :cover_image_url, PublicEventsEnhanced.get_cover_image_url(event))
      end)

    grouped =
      Enum.group_by(all_events_with_images, fn event ->
        cond do
          DateTime.compare(event.starts_at, now) == :lt -> :past
          DateTime.compare(event.starts_at, thirty_days_from_now) == :lt -> :upcoming
          true -> :future
        end
      end)

    %{
      upcoming: grouped[:upcoming] || [],
      future: grouped[:future] || [],
      # Past events are already in reverse chronological order (newest first)
      past: grouped[:past] || []
    }
  end

  defp get_recent_past_events(venue_id, opts) do
    alias EventasaurusDiscovery.PublicEvents.PublicEvent

    limit = Keyword.get(opts, :limit, 500)
    now = DateTime.utc_now()

    # Query past events in reverse chronological order (most recent first)
    from(pe in PublicEvent,
      where: pe.venue_id == ^venue_id,
      where:
        (not is_nil(pe.ends_at) and pe.ends_at < ^now) or
          (is_nil(pe.ends_at) and pe.starts_at < ^now),
      order_by: [desc: pe.starts_at],
      limit: ^limit
    )
    |> Repo.all()
    # Preload sources so get_cover_image_url can extract image URLs
    |> Repo.preload([:performers, :categories, :sources, venue: [city_ref: :country]])
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

  defp build_venue_breadcrumbs(venue) do
    base_items = [%{label: "Home", path: ~p"/"}]

    # Add city breadcrumb with metro area hierarchy if applicable
    items_with_city = add_venue_city_breadcrumb(base_items, venue)

    # Add Venues breadcrumb (links to city venues page)
    items_with_venues = add_venues_breadcrumb(items_with_city, venue)

    # Add current venue (no link)
    items_with_venues ++ [%{label: venue.name, path: nil}]
  end

  defp add_venue_city_breadcrumb(items, %{
         city_ref: %{id: city_id, slug: city_slug, name: city_name}
       }) do
    # Check if this city is part of a metro area (e.g., Paris 6 is part of Paris)
    case find_metro_primary_city(city_id) do
      nil ->
        # Standalone city or is itself the primary
        items ++ [%{label: city_name, path: ~p"/c/#{city_slug}"}]

      primary_city ->
        # City is part of a metro area - show hierarchy
        items ++
          [
            %{label: primary_city.name, path: ~p"/c/#{primary_city.slug}"},
            %{label: city_name, path: ~p"/c/#{city_slug}"}
          ]
    end
  end

  defp add_venue_city_breadcrumb(items, _venue) do
    # No city - just return base items
    items
  end

  defp add_venues_breadcrumb(items, %{city_ref: %{slug: city_slug}}) do
    # Add "Venues" breadcrumb linking to city venues page
    items ++ [%{label: "Venues", path: ~p"/c/#{city_slug}/venues"}]
  end

  defp add_venues_breadcrumb(items, _venue) do
    # No city - just return items without Venues breadcrumb
    items
  end

  defp find_metro_primary_city(city_id) do
    # Get the current city with coordinates
    current_city =
      Repo.one(
        from(c in City,
          where: c.id == ^city_id,
          select: %{
            id: c.id,
            name: c.name,
            slug: c.slug,
            latitude: c.latitude,
            longitude: c.longitude,
            country_id: c.country_id,
            discovery_enabled: c.discovery_enabled
          }
        )
      )

    # If the current city itself is discovery-enabled, it's the primary - don't add parent
    if current_city && current_city.discovery_enabled do
      nil
    else
      # Look for a nearby discovery-enabled city (the main city we promote)
      find_nearby_discovery_city(current_city)
    end
  end

  defp find_nearby_discovery_city(city) when is_nil(city), do: nil

  defp find_nearby_discovery_city(city) do
    if city.latitude && city.longitude do
      # Calculate bounding box for 50km radius (larger radius to catch main cities)
      lat = Decimal.to_float(city.latitude)
      lng = Decimal.to_float(city.longitude)

      lat_delta = 50.0 / 111.0
      lng_delta = 50.0 / (111.0 * :math.cos(lat * :math.pi() / 180.0))

      min_lat = lat - lat_delta
      max_lat = lat + lat_delta
      min_lng = lng - lng_delta
      max_lng = lng + lng_delta

      # Find the nearest discovery-enabled city
      Repo.one(
        from(c in City,
          where: c.country_id == ^city.country_id,
          where: c.discovery_enabled == true,
          where: not is_nil(c.latitude) and not is_nil(c.longitude),
          where: c.latitude >= ^min_lat and c.latitude <= ^max_lat,
          where: c.longitude >= ^min_lng and c.longitude <= ^max_lng,
          # Order by distance (approximation using lat/lng delta)
          order_by: [
            asc:
              fragment(
                "ABS(? - ?) + ABS(? - ?)",
                c.latitude,
                ^city.latitude,
                c.longitude,
                ^city.longitude
              )
          ],
          limit: 1,
          select: %{id: c.id, name: c.name, slug: c.slug}
        )
      )
    else
      nil
    end
  end

  # Generate combined JSON-LD schemas for venue page
  defp generate_json_ld_schemas(venue, breadcrumb_items, request_uri) do
    base_url = get_base_url_from_request(request_uri)

    # 1. LocalBusiness schema for the venue
    local_business_json = LocalBusinessSchema.generate(venue)

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

  # Build venue description for SEO meta tags
  defp build_venue_description(venue, events) do
    city_name = if venue.city_ref, do: venue.city_ref.name, else: nil
    upcoming_count = length(events.upcoming)

    cond do
      # If venue has address and city
      city_name && venue.address ->
        "#{venue.name} located at #{venue.address}, #{city_name}. " <>
          "Discover #{upcoming_count} upcoming events and activities."

      # If venue has city but no address
      city_name ->
        "#{venue.name} in #{city_name}. " <>
          "Discover #{upcoming_count} upcoming events and activities."

      # If venue has address but no city
      venue.address ->
        "#{venue.name} located at #{venue.address}. " <>
          "Discover #{upcoming_count} upcoming events and activities."

      # Fallback: just venue name
      true ->
        "#{venue.name} - Discover #{upcoming_count} upcoming events and activities."
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= if @loading do %>
        <div class="flex items-center justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
      <% else %>
        <!-- Hero Section -->
        <div class="bg-gray-50">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
            <!-- Breadcrumb -->
            <div class="mb-6">
              <Breadcrumbs.breadcrumb items={@breadcrumb_items} />
            </div>

            <!-- Venue Hero -->
            <div class="flex flex-col lg:flex-row gap-8">
              <!-- Venue Image (if available) -->
              <%= if has_venue_images?(@venue) do %>
                <div class="lg:w-2/5">
                  <div class="aspect-[4/3] rounded-xl overflow-hidden shadow-lg">
                    <ImageGallery.image_gallery venue={@venue} />
                  </div>
                </div>
              <% end %>

              <!-- Venue Details -->
              <div class={if has_venue_images?(@venue), do: "lg:w-3/5", else: "w-full"}>
                <h1 class="text-4xl font-bold text-gray-900 mb-6"><%= @venue.name %></h1>

                <div class="space-y-4">
                  <!-- Address -->
                  <%= if @venue.address do %>
                    <div class="flex items-start gap-3">
                      <svg
                        class="h-6 w-6 text-indigo-600 flex-shrink-0 mt-0.5"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
                        />
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"
                        />
                      </svg>
                      <div class="text-lg">
                        <div class="font-medium text-gray-900"><%= @venue.address %></div>
                        <%= if @venue.city_ref do %>
                          <div class="text-gray-600">
                            <%= @venue.city_ref.name %><%= if @venue.city_ref.country, do: ", #{@venue.city_ref.country.name}", else: "" %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Main Content -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">

          <!-- Events -->
          <div class="bg-white rounded-lg shadow-md p-6 mb-8">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">📅 Events at <%= @venue.name %></h2>

            <!-- Upcoming Events (Next 30 Days) -->
            <h3 class="text-lg font-medium text-gray-900 mb-3">
              Upcoming Events (Next 30 Days)
              <%= if length(@upcoming_events) > 0 do %>
                <span class="text-sm text-gray-500 font-normal">
                  (<%= length(@upcoming_events) %> total)
                </span>
              <% end %>
            </h3>
            <%= if Enum.empty?(@upcoming_events) do %>
              <p class="text-gray-600 mb-6">No events in the next 30 days.</p>
            <% else %>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-4">
                <%= for event <- Enum.take(@upcoming_events, @upcoming_visible_count) do %>
                  <.event_card event={event} language={@language} show_city={false} />
                <% end %>
              </div>
              <%= if length(@upcoming_events) > @upcoming_visible_count do %>
                <div class="text-center mb-6">
                  <button
                    type="button"
                    phx-click="load_more_upcoming"
                    class="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 border border-indigo-600 hover:border-indigo-800 rounded-lg transition-colors"
                  >
                    Load More (<%= length(@upcoming_events) - @upcoming_visible_count %> remaining)
                  </button>
                </div>
              <% end %>
            <% end %>

            <!-- Future Events (30+ Days) -->
            <%= if !Enum.empty?(@future_events) do %>
              <div class="border-t border-gray-200 pt-6 mb-6">
                <button
                  type="button"
                  phx-click="toggle_future_events"
                  class="flex items-center justify-between w-full text-left"
                >
                  <h3 class="text-lg font-medium text-gray-900">
                    Future Events (30+ Days)
                    <span class="text-sm text-gray-500 font-normal">
                      (<%= length(@future_events) %> total)
                    </span>
                  </h3>
                  <svg
                    class={
                      "w-5 h-5 transform transition-transform #{if @show_future_events, do: "rotate-180", else: ""}"
                    }
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 9l-7 7-7-7"
                    />
                  </svg>
                </button>

                <%= if @show_future_events do %>
                  <div class="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-4">
                    <%= for event <- Enum.take(@future_events, @future_visible_count) do %>
                      <div class="opacity-90">
                        <.event_card event={event} language={@language} show_city={false} />
                      </div>
                    <% end %>
                  </div>
                  <%= if length(@future_events) > @future_visible_count do %>
                    <div class="text-center">
                      <button
                        type="button"
                        phx-click="load_more_future"
                        class="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 border border-indigo-600 hover:border-indigo-800 rounded-lg transition-colors"
                      >
                        Load More (<%= length(@future_events) - @future_visible_count %> remaining)
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            <% end %>
            <!-- Past Events (Collapsible) -->
            <%= if !Enum.empty?(@past_events) do %>
              <div class="border-t border-gray-200 pt-6">
                <button
                  type="button"
                  phx-click="toggle_past_events"
                  class="flex items-center justify-between w-full text-left"
                >
                  <h3 class="text-lg font-medium text-gray-900">
                    Past Events
                    <span class="text-sm text-gray-500 font-normal">
                      (<%= length(@past_events) %> total)
                    </span>
                  </h3>
                  <svg
                    class={"w-5 h-5 transform transition-transform #{if @show_past_events, do: "rotate-180", else: ""}"}
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 9l-7 7-7-7"
                    />
                  </svg>
                </button>

                <%= if @show_past_events do %>
                  <div class="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-4">
                    <%= for event <- Enum.take(@past_events, @past_visible_count) do %>
                      <div class="opacity-75">
                        <.event_card event={event} language={@language} show_city={false} />
                      </div>
                    <% end %>
                  </div>
                  <%= if length(@past_events) > @past_visible_count do %>
                    <div class="text-center">
                      <button
                        type="button"
                        phx-click="load_more_past"
                        class="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 border border-indigo-600 hover:border-indigo-800 rounded-lg transition-colors"
                      >
                        Load More (<%= length(@past_events) - @past_visible_count %> remaining)
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>

          <!-- Location Map -->
          <div class="bg-white rounded-lg shadow-md p-6">
            <h2 class="text-xl font-semibold text-gray-900 mb-4">🗺️ Location</h2>
            <.live_component
              module={StaticMapComponent}
              id="venue-map"
              venue={@venue}
              theme={:professional}
              size={:large}
            />
          </div>
          <!-- Nearby Events -->
          <%= if !Enum.empty?(@nearby_events) do %>
            <div class="bg-white rounded-lg shadow-md p-6 mt-8">
              <h2 class="text-xl font-semibold text-gray-900 mb-4">
                🎉 More Events in <%= @venue.city_ref.name %>
              </h2>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                <%= for event <- @nearby_events do %>
                  <.event_card event={event} language={@language} show_city={false} />
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
