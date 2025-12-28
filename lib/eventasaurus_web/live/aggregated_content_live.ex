defmodule EventasaurusWeb.AggregatedContentLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.SourceStore
  alias EventasaurusDiscovery.AggregationTypeSlug
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainers
  alias EventasaurusWeb.Helpers.CategoryHelpers
  alias EventasaurusWeb.Helpers.CurrencyHelpers
  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.Components.Activity.AggregatedHeroCard
  alias EventasaurusWeb.JsonLd.ItemListSchema
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.UrlHelper

  # Multi-city route: /social/:identifier, /movies/:identifier, etc.
  # Content type is extracted from the URL path (first segment)
  # City will be determined from query params in handle_params
  @impl true
  def mount(%{"identifier" => identifier} = params, _session, socket)
      when not is_map_key(params, "city_slug") do
    # Capture request URI for building absolute URLs (ngrok support)
    request_uri = extract_request_uri(socket)

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
         |> assign(:is_multi_city_route, true)
         |> assign(:request_uri, request_uri)}
    end
  end

  # City-scoped route with explicit content type: /c/:city_slug/:content_type/:identifier
  @impl true
  def mount(
        %{"city_slug" => city_slug, "content_type" => content_type, "identifier" => identifier},
        _session,
        socket
      ) do
    # Capture request URI for building absolute URLs (ngrok support)
    request_uri = extract_request_uri(socket)

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
         |> assign(:is_multi_city_route, false)
         |> assign(:request_uri, request_uri)}
    end
  end

  # City-scoped route with implicit content type: /c/:city_slug/social/:identifier, /c/:city_slug/food/:identifier
  # Content type is extracted from URL path in handle_params
  @impl true
  def mount(
        %{"city_slug" => city_slug, "identifier" => identifier} = params,
        _session,
        socket
      )
      when not is_map_key(params, "content_type") do
    # Capture request URI for building absolute URLs (ngrok support)
    request_uri = extract_request_uri(socket)

    # Look up city
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/activities")}

      city ->
        # Content type will be extracted from URL path in handle_params
        {:ok,
         socket
         |> assign(:city, city)
         |> assign(:content_type, nil)
         |> assign(:content_type_slug, nil)
         |> assign(:identifier, identifier)
         |> assign(:scope, :city_only)
         |> assign(:page_title, nil)
         |> assign(:source_name, get_source_name(identifier))
         |> assign(:is_multi_city_route, false)
         |> assign(:request_uri, request_uri)}
    end
  end

  @impl true
  def handle_params(params, url, socket) do
    # Extract content type from URL path when not provided in params
    # Handles both multi-city routes (/social/:identifier) and
    # city-scoped routes with implicit type (/c/:city_slug/social/:identifier)
    socket =
      if is_nil(socket.assigns[:content_type]) do
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

    # Check if the identifier is actually a container slug
    # If so, redirect to the dedicated container route to avoid route collision
    identifier = socket.assigns.identifier
    city = socket.assigns.city

    case PublicEventContainers.get_container_by_slug(identifier) do
      %{slug: container_slug, container_type: container_type} = _container ->
        # Redirect to type-specific container route for semantic URLs
        # IMPORTANT: Use redirect/2 instead of push_navigate/2 because
        # the target route is in a different live_session (:city vs :catalog)
        type_plural =
          EventasaurusDiscovery.PublicEvents.PublicEventContainer.container_type_plural(
            container_type
          )

        {:noreply, redirect(socket, to: "/c/#{city.slug}/#{type_plural}/#{container_slug}")}

      nil ->
        # Not a container - continue with source aggregation
        socket = load_events(socket, scope)
        {:noreply, socket}
    end
  end

  # Extract content type slug from URL path
  # Handles both URL formats:
  # - "/social/pubquiz-pl" -> "social" (multi-city route, first segment)
  # - "/c/warsaw/social/pubquiz-pl" -> "social" (city-scoped route, third segment)
  defp extract_content_type_from_url(url) do
    segments =
      url
      |> URI.parse()
      |> Map.get(:path, "")
      |> String.split("/", trim: true)

    case segments do
      # City-scoped route: /c/:city_slug/:content_type/:identifier
      ["c", _city_slug, content_type, _identifier | _] -> content_type
      # Multi-city route: /:content_type/:identifier
      [content_type | _] -> content_type
      _ -> nil
    end
  end

  @impl true
  def handle_event("toggle_scope", %{"scope" => scope_str}, socket) do
    scope =
      case scope_str do
        "all_cities" -> :all_cities
        _ -> :city_only
      end

    # Navigate to appropriate route based on scope
    # IMPORTANT: Use redirect/2 instead of push_navigate/2 because the routes
    # are in different live_sessions (:catalog vs :city). Cross-session navigation
    # requires a full page load via redirect.
    url =
      if scope == :all_cities do
        # Expanding to all cities - use multi-city route (in :catalog live_session)
        # Multi-city routes use plural slugs: /festivals/:identifier, /social/:identifier
        multi_city_slug = singular_to_plural_slug(socket.assigns.content_type_slug)

        "/#{multi_city_slug}/#{socket.assigns.identifier}?scope=all&city=#{socket.assigns.city.slug}"
      else
        # Collapsing to city only - use city-scoped route (in :city live_session)
        # City-scoped routes use singular slugs: /c/:city_slug/:content_type/:identifier
        city_content_slug = plural_to_singular_slug(socket.assigns.content_type_slug)
        "/c/#{socket.assigns.city.slug}/#{city_content_slug}/#{socket.assigns.identifier}"
      end

    {:noreply, redirect(socket, to: url)}
  end

  # Load events based on scope - OPTIMIZED VERSION
  # Uses database-level aggregation for stats (COUNT, GROUP BY) and only fetches
  # the events needed for display (one per venue).
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
      # Get city coordinates for radius filtering
      center_lat = if city.latitude, do: Decimal.to_float(city.latitude), else: nil
      center_lng = if city.longitude, do: Decimal.to_float(city.longitude), else: nil

      # OPTIMIZED: Get aggregation stats using database-level COUNT/GROUP BY
      # This replaces fetching 500+ events just to count them
      stats =
        PublicEventsEnhanced.get_source_aggregation_stats(%{
          source_slug: identifier,
          center_lat: center_lat,
          center_lng: center_lng,
          radius_km: 50
        })

      # Extract stats (in_radius_count used internally, not needed as separate var)
      total_event_count = stats.total_count
      out_of_city_count = stats.out_of_radius_count
      unique_cities = stats.unique_cities
      city_stats = stats.city_stats

      # OPTIMIZED: Only fetch events needed for display (one per venue)
      # This replaces fetching ALL events and then grouping in Elixir
      {venue_groups, city_groups} =
        case scope do
          :all_cities ->
            # Get events grouped by city and venue - one per venue
            events_by_city =
              PublicEventsEnhanced.list_events_grouped_by_city_and_venue(%{
                source_slug: identifier,
                browsing_city_id: city.id
              })

            # Build city groups with distance info from stats
            groups = build_city_groups_from_stats(events_by_city, city_stats, city)
            {[], groups}

          :city_only ->
            # Get one event per venue within radius
            events =
              PublicEventsEnhanced.list_events_grouped_by_venue(%{
                source_slug: identifier,
                center_lat: center_lat,
                center_lng: center_lng,
                radius_km: 50,
                browsing_city_id: city.id
              })

            venue_groups =
              events
              |> Enum.map(fn event -> %{event: event} end)
              |> Enum.sort_by(fn %{event: event} ->
                event.venue && event.venue.name
              end)

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

      # Get events for JSON-LD schema (use what we already have)
      events_for_schema =
        case scope do
          :all_cities ->
            city_groups |> Enum.flat_map(& &1.venue_groups) |> Enum.map(& &1.event)

          :city_only ->
            venue_groups |> Enum.map(& &1.event)
        end

      # Generate JSON-LD structured data
      json_ld =
        ItemListSchema.generate(events_for_schema, content_type, identifier, city, max_items: 20)

      # Fetch source metadata for hero card theming
      # Prefer the URL's content_type_slug for theming when it matches a valid domain
      source = SourceStore.get_source_by_slug(identifier)
      content_type_slug = socket.assigns.content_type_slug
      source_domain = get_domain_for_theming(source, content_type_slug)
      source_logo_url = source && source.logo_url

      # Calculate location count based on scope
      location_count =
        case scope do
          :all_cities -> total_event_count
          :city_only -> length(venue_groups)
        end

      # Build aggregation data struct for Open Graph (includes all data needed for social card)
      aggregation_data = %{
        city: city,
        content_type: content_type,
        identifier: identifier,
        source_name: socket.assigns.source_name,
        total_event_count: total_event_count,
        location_count: location_count,
        hero_image: hero_image
      }

      # Generate Open Graph meta tags with branded social card URL
      og_tags = build_aggregation_open_graph(aggregation_data, socket.assigns.request_uri)

      socket
      |> assign(:scope, scope)
      |> assign(:page_title, page_title)
      |> assign(:venue_schedules, venue_groups)
      |> assign(:city_groups, city_groups)
      |> assign(:out_of_city_count, out_of_city_count)
      |> assign(:unique_cities, unique_cities)
      |> assign(:total_event_count, total_event_count)
      |> assign(:location_count, location_count)
      |> assign(:hero_image, hero_image)
      |> assign(:breadcrumb_items, breadcrumb_items)
      |> assign(:json_ld, json_ld)
      |> assign(:open_graph, og_tags)
      |> assign(:source_domain, source_domain)
      |> assign(:source_logo_url, source_logo_url)
    end
  end

  # Build city groups from pre-computed stats and events
  # This is more efficient than computing distances and counts from full events
  defp build_city_groups_from_stats(events_by_city, city_stats, current_city) do
    # Build a lookup map from city_stats for quick access
    stats_by_city_id =
      city_stats
      |> Enum.map(fn stat -> {stat.city_id, stat} end)
      |> Enum.into(%{})

    events_by_city
    |> Enum.map(fn {city_id, events} ->
      stat = Map.get(stats_by_city_id, city_id, %{})
      first_event = List.first(events)
      city = first_event && first_event.venue && first_event.venue.city_ref

      venue_groups =
        events
        |> Enum.map(fn event -> %{event: event} end)
        |> Enum.sort_by(fn %{event: event} -> event.venue && event.venue.name end)

      %{
        city: city,
        city_id: city_id,
        distance_km: stat[:distance_km],
        event_count: stat[:event_count] || length(events),
        venue_groups: venue_groups,
        is_current: city_id == current_city.id
      }
    end)
    |> Enum.reject(fn group -> is_nil(group.city) end)
    |> Enum.sort_by(fn group ->
      # Sort: current city first, then by distance
      if group.is_current, do: {0, 0}, else: {1, group.distance_km || 999_999}
    end)
  end

  # Get domain for theming - prefer URL content_type_slug when it's a valid theme domain
  # This ensures /festival/week_pl shows festival theme, not food theme
  defp get_domain_for_theming(source, content_type_slug) do
    # Map URL slugs to theme domains
    url_domain = slug_to_theme_domain(content_type_slug)

    # If URL domain is valid and source supports it, use URL domain for theming
    # Otherwise fall back to source's primary domain
    if url_domain && source && source_has_domain?(source, url_domain) do
      url_domain
    else
      get_primary_domain(source)
    end
  end

  # Map URL content_type slugs to theme domain names
  # Handles both singular (from city-scoped routes) and plural (from multi-city routes)
  # e.g., "festival" -> "festival", "festivals" -> "festival"
  defp slug_to_theme_domain("social"), do: "trivia"
  defp slug_to_theme_domain("food"), do: "food"
  defp slug_to_theme_domain("festival"), do: "festival"
  defp slug_to_theme_domain("festivals"), do: "festival"
  defp slug_to_theme_domain("music"), do: "music"
  defp slug_to_theme_domain("movies"), do: "movies"
  defp slug_to_theme_domain("screening"), do: "movies"
  defp slug_to_theme_domain("comedy"), do: "comedy"
  defp slug_to_theme_domain("theater"), do: "theater"
  defp slug_to_theme_domain("theatre"), do: "theater"
  defp slug_to_theme_domain("sports"), do: "sports"
  defp slug_to_theme_domain("happenings"), do: nil
  defp slug_to_theme_domain("dance"), do: nil
  defp slug_to_theme_domain("classes"), do: nil
  defp slug_to_theme_domain(_), do: nil

  # Convert plural URL slugs to singular for city-scoped routes
  # Multi-city routes use plural: /festivals/week_pl
  # City-scoped routes use singular: /krakow/festival/week_pl
  defp plural_to_singular_slug("festivals"), do: "festival"
  defp plural_to_singular_slug("happenings"), do: "happenings"
  defp plural_to_singular_slug("classes"), do: "classes"
  defp plural_to_singular_slug(slug), do: slug

  # Convert singular URL slugs to plural for multi-city routes
  # City-scoped routes use singular: /krakow/festival/week_pl
  # Multi-city routes use plural: /festivals/week_pl
  defp singular_to_plural_slug("festival"), do: "festivals"
  defp singular_to_plural_slug("happenings"), do: "happenings"
  defp singular_to_plural_slug("classes"), do: "classes"
  defp singular_to_plural_slug(slug), do: slug

  # Check if source has a specific domain in its domains list
  defp source_has_domain?(%{domains: domains}, domain) when is_list(domains) do
    domain in domains
  end

  defp source_has_domain?(_, _), do: false

  # Get primary domain from source for theming (fallback)
  defp get_primary_domain(nil), do: nil

  defp get_primary_domain(%{domains: domains}) when is_list(domains) and length(domains) > 0 do
    List.first(domains)
  end

  defp get_primary_domain(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <!-- Breadcrumbs (outside hero card, like activity pages) -->
        <nav class="mb-4">
          <Breadcrumbs.breadcrumb items={@breadcrumb_items} />
        </nav>

        <!-- Hero Section -->
        <AggregatedHeroCard.aggregated_hero_card
          source_name={@source_name}
          source_logo_url={@source_logo_url}
          city={@city}
          content_type={@content_type}
          domain={@source_domain}
          hero_image={@hero_image}
          total_event_count={@total_event_count}
          location_count={@location_count}
          unique_cities={@unique_cities}
          out_of_city_count={@out_of_city_count}
          scope={@scope}
        />
      </div>

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

  # Format datetime with timezone conversion
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
  defp build_aggregation_open_graph(aggregation_data, request_uri) do
    %{
      content_type: content_type,
      identifier: identifier,
      city: city,
      total_event_count: total_event_count,
      source_name: source_name
    } = aggregation_data

    # Convert schema type to friendly name
    type_name = schema_type_to_friendly_name(content_type)

    # Build title and description using source_name (already formatted)
    title = "#{source_name} - #{type_name} in #{city.name}"

    description =
      "Discover #{source_name} #{type_name} in #{city.name}. #{total_event_count} #{pluralize("event", total_event_count)} available."

    # Generate branded social card URL using HashGenerator with request_uri for ngrok support
    social_card_path = HashGenerator.generate_url_path(aggregation_data, :source_aggregation)
    image_url = UrlHelper.build_url(social_card_path, request_uri)

    # Build canonical URL with request_uri for ngrok support
    content_type_slug = EventasaurusDiscovery.AggregationTypeSlug.to_slug(content_type)
    canonical_path = "/c/#{city.slug}/#{content_type_slug}/#{identifier}"
    canonical_url = UrlHelper.build_url(canonical_path, request_uri)

    # Generate Open Graph tags
    # Social card is 800x419 (1.91:1 ratio), same as other branded cards
    Phoenix.HTML.Safe.to_iodata(
      EventasaurusWeb.Components.OpenGraphComponent.open_graph_tags(%{
        type: "website",
        title: title,
        description: description,
        image_url: image_url,
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

  # Extract request URI from socket for building absolute URLs (ngrok support)
  defp extract_request_uri(socket) do
    raw_uri = get_connect_info(socket, :uri)

    cond do
      match?(%URI{}, raw_uri) -> raw_uri
      is_binary(raw_uri) -> URI.parse(raw_uri)
      true -> nil
    end
  end
end
