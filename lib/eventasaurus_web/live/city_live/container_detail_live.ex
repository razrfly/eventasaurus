defmodule EventasaurusWeb.CityLive.ContainerDetailLive do
  @moduledoc """
  LiveView for container detail pages (festivals, conferences, tours, etc.).

  Displays all events within a container with grouping by date/venue.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEvents.{PublicEventContainers, PublicEventContainer}
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusWeb.Components.Breadcrumbs
  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
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
        # Get language from session or default to English
        language = get_connect_params(socket)["locale"] || "en"

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

        # Build breadcrumb items
        breadcrumb_items =
          BreadcrumbBuilder.build_container_breadcrumbs(container, city,
            gettext_backend: EventasaurusWeb.Gettext
          )

        # Generate breadcrumb JSON-LD structured data
        base_url = EventasaurusWeb.Endpoint.url()

        canonical_url =
          "#{base_url}/c/#{city.slug}/#{PublicEventContainer.container_type_plural(container.container_type)}/#{container.slug}"

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
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
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
        <div class="bg-white shadow-sm border-b">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <!-- Breadcrumbs -->
            <Breadcrumbs.breadcrumb items={@breadcrumb_items} />

            <div class="flex items-start justify-between">
              <div class="flex-1">
                <div class="flex items-center space-x-3 mb-2">
                  <h1 class="text-4xl font-bold text-gray-900">
                    <%= @container.title %>
                  </h1>
                  <span class={"px-3 py-1 rounded-md text-sm font-medium text-white #{get_badge_color(@container.container_type)}"}>
                    <%= PublicEventContainer.container_type_label(@container) %>
                  </span>
                </div>

                <div class="flex flex-wrap gap-4 mt-4 text-gray-600">
                  <div class="flex items-center">
                    <Heroicons.calendar class="w-5 h-5 mr-2" />
                    <span class="font-medium">
                      <%= format_date_range(@container) %>
                    </span>
                  </div>

                  <div class="flex items-center">
                    <Heroicons.map_pin class="w-5 h-5 mr-2" />
                    <span><%= @city.name %></span>
                  </div>

                  <div class="flex items-center">
                    <Heroicons.ticket class="w-5 h-5 mr-2" />
                    <span><%= length(@events) %> events</span>
                  </div>

                  <%= if @container.description do %>
                    <div class="w-full mt-2">
                      <p class="text-gray-700"><%= @container.description %></p>
                    </div>
                  <% end %>
                </div>
              </div>

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
            </div>
          </div>
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

            <!-- Container Sources -->
            <%= if @container do %>
              <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-12 pt-8 border-t border-gray-200">
                <h3 class="text-sm font-medium text-gray-500 mb-3">
                  Event Data Sources
                </h3>
                <div class="flex flex-wrap gap-4">
                  <%= if @container.source do %>
                    <% source_url = get_container_source_url(@container) %>
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
                        Last updated <%= format_relative_time(@container.updated_at) %>
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

  defp get_badge_color(:festival), do: "bg-purple-500"
  defp get_badge_color(:conference), do: "bg-orange-500"
  defp get_badge_color(:tour), do: "bg-red-500"
  defp get_badge_color(:series), do: "bg-indigo-500"
  defp get_badge_color(:exhibition), do: "bg-yellow-500"
  defp get_badge_color(:tournament), do: "bg-pink-500"
  defp get_badge_color(_), do: "bg-gray-500"

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

  defp format_relative_time(nil), do: "unknown"

  defp format_relative_time(%NaiveDateTime{} = naive_datetime) do
    # Convert NaiveDateTime to DateTime (assume UTC)
    datetime = DateTime.from_naive!(naive_datetime, "Etc/UTC")
    format_relative_time(datetime)
  end

  defp format_relative_time(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      diff < 86400 -> "#{div(diff, 3600)} hours ago"
      diff < 604_800 -> "#{div(diff, 86400)} days ago"
      diff < 2_592_000 -> "#{div(diff, 604_800)} weeks ago"
      true -> "#{div(diff, 2_592_000)} months ago"
    end
  end

  defp get_container_source_url(container) do
    cond do
      # Priority 1: Try source_event sources
      url = get_url_from_source_event(container.source_event) ->
        url

      # Priority 2: Construct from container metadata (Resident Advisor)
      umbrella_event_id = get_in(container.metadata, ["umbrella_event_id"]) ->
        # Resident Advisor event URL format
        "https://ra.co/events/#{umbrella_event_id}"

      true ->
        nil
    end
  end

  defp get_url_from_source_event(nil), do: nil

  defp get_url_from_source_event(%{sources: sources}) when is_list(sources) do
    Enum.find_value(sources, fn source ->
      cond do
        # Priority 1: source_url field
        source.source_url && source.source_url != "" ->
          source.source_url

        # Priority 2: metadata URLs
        url = get_in(source.metadata, ["url"]) ->
          url

        url = get_in(source.metadata, ["event_url"]) ->
          url

        true ->
          nil
      end
    end)
  end

  defp get_url_from_source_event(_), do: nil

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
                <img src={Map.get(@event, :cover_image_url)} alt={@event.title} class="w-full h-full object-cover" loading="lazy">
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
