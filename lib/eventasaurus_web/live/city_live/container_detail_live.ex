defmodule EventasaurusWeb.CityLive.ContainerDetailLive do
  @moduledoc """
  LiveView for container detail pages (festivals, conferences, tours, etc.).

  Displays all events within a container with grouping by date/venue.
  """

  use EventasaurusWeb, :live_view

  alias Eventasaurus.CDN
  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEvents.{PublicEventContainers, PublicEventContainer}
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.Components.Activity.ContainerHeroCard
  alias EventasaurusWeb.Helpers.{BreadcrumbBuilder, SourceAttribution}
  alias EventasaurusWeb.JsonLd.BreadcrumbListSchema

  @impl true
  def mount(%{"city_slug" => city_slug, "container_slug" => container_slug}, _session, socket) do
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/activities")}

      city ->
        # Get language from connect params (safe nil handling) or default to English
        params = get_connect_params(socket) || %{}
        language = params["locale"] || "en"

        {:ok,
         socket
         |> assign(:city, city)
         |> assign(:container_slug, container_slug)
         |> assign(:language, language)
         |> assign(:view_mode, "grid")
         |> assign(:loading, true)
         |> assign(:container, nil)
         |> assign(:events, [])}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket = load_container_and_events(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_view", %{"view" => view_mode}, socket) do
    {:noreply, assign(socket, :view_mode, view_mode)}
  end

  @impl true
  def handle_event("change_language", %{"language" => language}, socket) do
    socket =
      socket
      |> assign(:language, language)
      |> Phoenix.LiveView.push_event("set_language_cookie", %{language: language})

    {:noreply, socket}
  end

  defp load_container_and_events(socket) do
    city = socket.assigns.city
    container_slug = socket.assigns.container_slug

    # Find container by slug (slug contains random suffix, so we need to search)
    # For now, let's get all containers and find by slug match
    case find_container_by_slug(container_slug, city.id) do
      nil ->
        socket
        |> put_flash(:error, "Container not found")
        |> push_navigate(to: ~p"/c/#{city.slug}")
        |> assign(:loading, false)

      container ->
        # Fetch all events for this container
        raw_events = PublicEventContainers.get_container_events(container)

        # Filter to city events only, then enrich with cover images
        events =
          raw_events
          |> Enum.filter(&belongs_to_city?(&1, city.id))
          |> Enum.map(fn event ->
            Map.put(event, :cover_image_url, PublicEventsEnhanced.get_cover_image_url(event))
          end)

        # Group events by date
        grouped_events = group_events_by_date(events)

        # Extract hero image from first event with an image
        hero_image =
          events
          |> Enum.find_value(fn event -> Map.get(event, :cover_image_url) end)

        # Get source logo if available
        source_logo_url = container.source && container.source.logo_url

        # Build breadcrumb items
        breadcrumb_items =
          BreadcrumbBuilder.build_container_breadcrumbs(container, city,
            gettext_backend: EventasaurusWeb.Gettext
          )

        # Generate breadcrumb JSON-LD structured data
        base_url = EventasaurusWeb.Endpoint.url()

        # Use type-specific route for semantic URLs
        type_plural = PublicEventContainer.container_type_plural(container.container_type)

        canonical_url =
          "#{base_url}/c/#{city.slug}/#{type_plural}/#{container.slug}"

        breadcrumb_json_ld =
          BreadcrumbListSchema.from_breadcrumb_builder_items(
            breadcrumb_items,
            canonical_url,
            base_url
          )

        socket
        |> assign(:container, container)
        |> assign(:events, events)
        |> assign(:grouped_events, grouped_events)
        |> assign(:hero_image, hero_image)
        |> assign(:source_logo_url, source_logo_url)
        |> assign(:breadcrumb_items, breadcrumb_items)
        |> assign(:json_ld, breadcrumb_json_ld)
        |> assign(:canonical_url, canonical_url)
        |> assign(:loading, false)
        |> assign(:page_title, container.title)
        |> assign(:meta_description, build_meta_description(container))
    end
  end

  defp find_container_by_slug(slug, city_id) do
    # Fetch container by slug directly (avoids N+1)
    with %PublicEventContainer{} = container <- PublicEventContainers.get_container_by_slug(slug),
         true <- has_events_in_city?(container, city_id) do
      container
    else
      _ -> nil
    end
  end

  defp has_events_in_city?(container, city_id) do
    events = PublicEventContainers.get_container_events(container)

    Enum.any?(events, fn event ->
      event.venue && event.venue.city_id == city_id
    end)
  end

  defp belongs_to_city?(%{venue: %{city_id: city_id}}, city_id), do: true
  defp belongs_to_city?(_, _), do: false

  defp group_events_by_date(events) do
    events
    |> Enum.group_by(fn event ->
      if event.starts_at do
        Date.to_iso8601(DateTime.to_date(event.starts_at))
      else
        "TBD"
      end
    end)
    |> Enum.sort_by(fn {date, _events} -> date end)
  end

  defp build_meta_description(container) do
    type_label = PublicEventContainer.container_type_label(container)
    count = container |> PublicEventContainers.get_container_events() |> length()
    "#{type_label} with #{count} events. #{format_date_range(container)}"
  end

  defp format_date_range(container) do
    if container.end_date do
      "#{format_date(container.start_date)} - #{format_date(container.end_date)}"
    else
      "Starting #{format_date(container.start_date)}"
    end
  end

  defp format_date(nil), do: "TBD"

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_datetime(nil), do: "TBD"

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= if @loading do %>
        <div class="flex justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
        </div>
      <% else %>
        <!-- Hero Section -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <!-- Breadcrumbs (outside hero card, like activity pages) -->
          <nav class="mb-4">
            <Breadcrumbs.breadcrumb items={@breadcrumb_items} />
          </nav>

          <!-- Container Hero Card -->
          <ContainerHeroCard.container_hero_card
            title={@container.title}
            container_type={@container.container_type}
            description={@container.description}
            city={@city}
            hero_image={@hero_image}
            event_count={length(@events)}
            start_date={@container.start_date}
            end_date={@container.end_date}
            logo_url={@source_logo_url}
          />
        </div>

        <!-- View Mode Toggle -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex justify-end">
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
          </div>
        </div>

        <!-- Events List (Grouped by Date) -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pb-8">
          <%= if @events == [] do %>
            <div class="text-center py-12">
              <Heroicons.calendar_days class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-lg font-medium text-gray-900">
                No events found
              </h3>
              <p class="mt-1 text-sm text-gray-500">
                This container doesn't have any events yet.
              </p>
            </div>
          <% else %>
            <%= if @view_mode == "grid" do %>
              <!-- Grid View -->
              <%= for {date_str, date_events} <- @grouped_events do %>
                <div class="mb-8">
                  <h2 class="text-2xl font-bold text-gray-900 mb-4">
                    <%= format_date_header(date_str) %>
                  </h2>

                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    <%= for event <- date_events do %>
                      <.event_grid_item event={event} language={@language} />
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% else %>
              <!-- List View -->
              <%= for {date_str, date_events} <- @grouped_events do %>
                <div class="mb-8">
                  <h2 class="text-2xl font-bold text-gray-900 mb-4">
                    <%= format_date_header(date_str) %>
                  </h2>

                  <div class="space-y-4">
                    <%= for event <- date_events do %>
                      <.event_list_item event={event} language={@language} />
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% end %>

            <!-- Container Sources -->
            <%= if @container do %>
              <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-12 pt-8 border-t border-gray-200">
                <h3 class="text-sm font-medium text-gray-500 mb-3">
                  Event Data Sources
                </h3>
                <div class="flex flex-wrap gap-4">
                  <%= if @container.source do %>
                    <% source_url = SourceAttribution.get_container_source_url(@container) %>
                    <div class="text-sm">
                      <%= if source_url do %>
                        <a href={source_url} target="_blank" rel="noopener noreferrer" class="font-medium text-blue-600 hover:text-blue-800">
                          <%= @container.source.name %>
                          <Heroicons.arrow_top_right_on_square class="w-3 h-3 inline ml-1" />
                        </a>
                      <% else %>
                        <span class="font-medium text-gray-700">
                          <%= @container.source.name %>
                        </span>
                      <% end %>
                      <span class="text-gray-500 ml-2">
                        Last updated <%= SourceAttribution.format_relative_time(@container.updated_at) %>
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>

    <div id="language-cookie-hook" phx-hook="LanguageCookie"></div>
    """
  end

  defp format_date_header("TBD"), do: "Date TBD"

  defp format_date_header(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        today = Date.utc_today()

        cond do
          Date.compare(date, today) == :eq ->
            "Today, #{Calendar.strftime(date, "%B %d, %Y")}"

          Date.compare(date, Date.add(today, 1)) == :eq ->
            "Tomorrow, #{Calendar.strftime(date, "%B %d, %Y")}"

          true ->
            Calendar.strftime(date, "%A, %B %d, %Y")
        end

      _ ->
        date_str
    end
  end

  # Component for event grid item (card layout for grid view)
  defp event_grid_item(assigns) do
    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block group">
      <div class="bg-white rounded-lg shadow hover:shadow-lg transition-all duration-200 overflow-hidden h-full flex flex-col">
        <!-- Event Image -->
        <div class="relative w-full h-48 bg-gray-200 overflow-hidden">
          <%= if Map.get(@event, :cover_image_url) do %>
            <img
              src={CDN.url(Map.get(@event, :cover_image_url), width: 600, height: 384, fit: "cover", quality: 85)}
              alt={@event.title}
              class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-200"
              loading="lazy"
            >
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
              </svg>
            </div>
          <% end %>
        </div>

        <!-- Event Content -->
        <div class="p-4 flex-1 flex flex-col">
          <h3 class="text-lg font-semibold text-gray-900 mb-2 line-clamp-2 group-hover:text-blue-600 transition-colors">
            <%= Map.get(@event, :display_title) || @event.title %>
          </h3>

          <div class="mt-auto space-y-2">
            <div class="flex items-center text-sm text-gray-600">
              <Heroicons.calendar class="w-4 h-4 mr-2 flex-shrink-0" />
              <span class="truncate"><%= format_datetime(@event.starts_at) %></span>
            </div>

            <%= if venue = @event.venue do %>
              <div class="flex items-center text-sm text-gray-600">
                <Heroicons.map_pin class="w-4 h-4 mr-2 flex-shrink-0" />
                <span class="truncate"><%= venue.name %></span>
              </div>
            <% end %>
          </div>

          <%= if Map.get(@event, :display_description) do %>
            <p class="mt-3 text-sm text-gray-600 line-clamp-2">
              <%= Map.get(@event, :display_description) %>
            </p>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # Component for event list item (reuse from EventCards or define here)
  defp event_list_item(assigns) do
    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block">
      <div class="bg-white rounded-lg shadow hover:shadow-md transition-shadow p-6">
        <div class="flex gap-6">
          <!-- Event Image -->
          <div class="flex-shrink-0">
            <div class="w-24 h-24 bg-gray-200 rounded-lg overflow-hidden">
              <%= if Map.get(@event, :cover_image_url) do %>
                <img src={CDN.url(Map.get(@event, :cover_image_url), width: 192, height: 192, fit: "cover", quality: 85)} alt={@event.title} class="w-full h-full object-cover" loading="lazy">
              <% else %>
                <div class="w-full h-full flex items-center justify-center">
                  <svg class="w-8 h-8 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
                  </svg>
                </div>
              <% end %>
            </div>
          </div>

          <div class="flex-1">
            <h3 class="text-xl font-semibold text-gray-900">
              <%= Map.get(@event, :display_title) || @event.title %>
            </h3>

            <div class="mt-2 flex flex-wrap gap-4 text-sm text-gray-600">
              <div class="flex items-center">
                <Heroicons.calendar class="w-4 h-4 mr-1" />
                <%= format_datetime(@event.starts_at) %>
              </div>

              <%= if venue = @event.venue do %>
                <div class="flex items-center">
                  <Heroicons.map_pin class="w-4 h-4 mr-1" />
                  <%= venue.name %>
                </div>
              <% end %>
            </div>

            <%= if Map.get(@event, :display_description) do %>
              <p class="mt-3 text-gray-600 line-clamp-2">
                <%= Map.get(@event, :display_description) %>
              </p>
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end
end
