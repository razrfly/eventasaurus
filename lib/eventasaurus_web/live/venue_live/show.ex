defmodule EventasaurusWeb.VenueLive.Show do
  use EventasaurusWeb, :live_view

  alias Eventasaurus.CDN
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.PublicEvents
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusWeb.Components.OpenGraphComponent
  alias EventasaurusWeb.Components.Activity.VenueHeroCard
  alias EventasaurusWeb.Components.Activity.VenueLocationCard
  alias EventasaurusWeb.Components.Activity.ActivityLayout
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.Helpers.{BreadcrumbBuilder, LanguageDiscovery, SEOHelpers}
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
      |> assign(:available_languages, ["en"])
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
  def handle_params(
        %{"venue_slug" => venue_slug, "city_slug" => city_slug} = _params,
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

  # Shared logic for loading and assigning venue data to socket
  defp load_and_assign_venue(venue, socket) do
    # Preload city and country (venue_images is a field, not an association)
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

    # Build venue description for SEO
    description = build_venue_description(venue, events)

    # Build canonical path
    canonical_path =
      if venue.city_ref do
        "/c/#{venue.city_ref.slug}/venues/#{venue.slug}"
      else
        "/venues/#{venue.slug}"
      end

    # Generate Open Graph meta tags
    og_tags =
      build_venue_open_graph(venue, description, canonical_path, socket.assigns.request_uri)

    socket =
      socket
      |> assign(:venue, venue)
      |> assign(:upcoming_events, events.upcoming)
      |> assign(:future_events, events.future)
      |> assign(:past_events, events.past)
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

  # Build Open Graph meta tags for venue pages
  defp build_venue_open_graph(venue, description, canonical_path, request_uri) do
    # Build absolute canonical URL using UrlHelper to avoid double slash issues
    canonical_url = UrlHelper.build_url(canonical_path, request_uri)

    # Use venue cover image if available, otherwise placeholder
    # Venue.get_cover_image/2 handles the smart fallback chain (venue images -> city gallery)
    cdn_image_url =
      case Venue.get_cover_image(venue, width: 1200, height: 630, quality: 85) do
        {:ok, url, _source} ->
          url

        {:error, :no_image} ->
          venue_name_encoded = URI.encode(venue.name)
          CDN.url("https://placehold.co/1200x630/4ECDC4/FFFFFF?text=#{venue_name_encoded}")
      end

    # Generate Open Graph tags
    Phoenix.HTML.Safe.to_iodata(
      OpenGraphComponent.open_graph_tags(%{
        type: "place",
        title: "#{venue.name} · Wombie",
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
    <div class="min-h-screen">
      <%= if @loading do %>
        <div class="flex items-center justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
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
            upcoming_event_count={length(@upcoming_events) + length(@future_events)}
          />
        </div>

        <!-- Main Content with Two-Column Layout -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <ActivityLayout.activity_layout>
            <:main>
              <!-- Events Section -->
              <div class="space-y-8">
                <!-- Upcoming Events (Next 30 Days) -->
                <div>
                  <h2 class="text-2xl font-bold text-gray-900 mb-2">
                    <%= gettext("Upcoming Events") %>
                  </h2>
                  <p class="text-gray-600 mb-6">
                    <%= gettext("Next 30 days") %>
                    <%= if length(@upcoming_events) > 0 do %>
                      <span class="text-gray-500">
                        · <%= length(@upcoming_events) %> <%= ngettext("event", "events", length(@upcoming_events)) %>
                      </span>
                    <% end %>
                  </p>

                  <%= if Enum.empty?(@upcoming_events) do %>
                    <div class="bg-gray-50 rounded-lg p-8 text-center">
                      <Heroicons.calendar class="w-12 h-12 text-gray-400 mx-auto mb-3" />
                      <p class="text-gray-600"><%= gettext("No events in the next 30 days.") %></p>
                    </div>
                  <% else %>
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                      <%= for event <- Enum.take(@upcoming_events, @upcoming_visible_count) do %>
                        <.event_card event={event} language={@language} show_city={false} />
                      <% end %>
                    </div>
                    <%= if length(@upcoming_events) > @upcoming_visible_count do %>
                      <div class="text-center mt-6">
                        <button
                          type="button"
                          phx-click="load_more_upcoming"
                          class="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 border border-indigo-600 hover:border-indigo-800 rounded-lg transition-colors"
                        >
                          <%= gettext("Load More") %> (<%= length(@upcoming_events) - @upcoming_visible_count %> <%= gettext("remaining") %>)
                        </button>
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <!-- Future Events (30+ Days) - Collapsible -->
                <%= if !Enum.empty?(@future_events) do %>
                  <div class="border-t border-gray-200 pt-8">
                    <button
                      type="button"
                      phx-click="toggle_future_events"
                      class="flex items-center justify-between w-full text-left group"
                    >
                      <div>
                        <h2 class="text-xl font-semibold text-gray-900 group-hover:text-indigo-600 transition-colors">
                          <%= gettext("Future Events") %>
                        </h2>
                        <p class="text-sm text-gray-500">
                          <%= gettext("30+ days away") %> · <%= length(@future_events) %> <%= ngettext("event", "events", length(@future_events)) %>
                        </p>
                      </div>
                      <Heroicons.chevron_down class={"w-5 h-5 text-gray-500 transform transition-transform #{if @show_future_events, do: "rotate-180", else: ""}"} />
                    </button>

                    <%= if @show_future_events do %>
                      <div class="mt-6 grid grid-cols-1 md:grid-cols-2 gap-6">
                        <%= for event <- Enum.take(@future_events, @future_visible_count) do %>
                          <div class="opacity-90">
                            <.event_card event={event} language={@language} show_city={false} />
                          </div>
                        <% end %>
                      </div>
                      <%= if length(@future_events) > @future_visible_count do %>
                        <div class="text-center mt-6">
                          <button
                            type="button"
                            phx-click="load_more_future"
                            class="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 border border-indigo-600 hover:border-indigo-800 rounded-lg transition-colors"
                          >
                            <%= gettext("Load More") %> (<%= length(@future_events) - @future_visible_count %> <%= gettext("remaining") %>)
                          </button>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                <% end %>

                <!-- Past Events - Collapsible -->
                <%= if !Enum.empty?(@past_events) do %>
                  <div class="border-t border-gray-200 pt-8">
                    <button
                      type="button"
                      phx-click="toggle_past_events"
                      class="flex items-center justify-between w-full text-left group"
                    >
                      <div>
                        <h2 class="text-xl font-semibold text-gray-900 group-hover:text-indigo-600 transition-colors">
                          <%= gettext("Past Events") %>
                        </h2>
                        <p class="text-sm text-gray-500">
                          <%= length(@past_events) %> <%= ngettext("event", "events", length(@past_events)) %>
                        </p>
                      </div>
                      <Heroicons.chevron_down class={"w-5 h-5 text-gray-500 transform transition-transform #{if @show_past_events, do: "rotate-180", else: ""}"} />
                    </button>

                    <%= if @show_past_events do %>
                      <div class="mt-6 grid grid-cols-1 md:grid-cols-2 gap-6">
                        <%= for event <- Enum.take(@past_events, @past_visible_count) do %>
                          <div class="opacity-75">
                            <.event_card event={event} language={@language} show_city={false} />
                          </div>
                        <% end %>
                      </div>
                      <%= if length(@past_events) > @past_visible_count do %>
                        <div class="text-center mt-6">
                          <button
                            type="button"
                            phx-click="load_more_past"
                            class="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 border border-indigo-600 hover:border-indigo-800 rounded-lg transition-colors"
                          >
                            <%= gettext("Load More") %> (<%= length(@past_events) - @past_visible_count %> <%= gettext("remaining") %>)
                          </button>
                        </div>
                      <% end %>
                    <% end %>
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
