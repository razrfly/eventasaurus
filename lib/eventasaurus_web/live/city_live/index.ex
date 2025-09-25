defmodule EventasaurusWeb.CityLive.Index do
  @moduledoc """
  LiveView for city-based event discovery pages.

  Displays events within a configurable radius of a city's center,
  using the city's dynamically calculated coordinates.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Locations

  @default_radius_km 25
  @max_radius_km 100
  @min_radius_km 5

  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/activities")}

      city ->
        if city.latitude && city.longitude do
          {:ok,
           socket
           |> assign(:city, city)
           |> assign(:radius_km, @default_radius_km)
           |> assign(:loading, false)
           |> assign(:page_title, page_title(city))
           |> assign(:meta_description, meta_description(city))
           |> fetch_events()
           |> fetch_nearby_cities()}
        else
          {:ok,
           socket
           |> put_flash(:error, "City location data is being processed. Please try again later.")
           |> push_navigate(to: ~p"/activities")}
        end
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    radius = parse_radius(params["radius"])

    socket =
      if radius != socket.assigns.radius_km do
        socket
        |> assign(:radius_km, radius)
        |> fetch_events()
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_radius", %{"radius" => radius_str}, socket) do
    radius_km = String.to_integer(radius_str)

    socket =
      socket
      |> assign(:radius_km, radius_km)
      |> assign(:loading, true)
      |> fetch_events()
      |> push_patch(to: ~p"/c/#{socket.assigns.city.slug}?radius=#{radius_km}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_timeframe", %{"timeframe" => timeframe}, socket) do
    path =
      case timeframe do
        "today" -> ~p"/c/#{socket.assigns.city.slug}/events/today"
        "weekend" -> ~p"/c/#{socket.assigns.city.slug}/events/weekend"
        "week" -> ~p"/c/#{socket.assigns.city.slug}/events/week"
        _ -> ~p"/c/#{socket.assigns.city.slug}/events"
      end

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <div class="bg-white shadow-sm border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex justify-between items-center">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">
                Events in {@city.name}
              </h1>
              <p class="text-sm text-gray-600 mt-1">
                {@city.country.name} · <%= length(@events) %> upcoming events within {@radius_km}km
              </p>
            </div>

            <!-- Radius Selector -->
            <div class="bg-gray-50 rounded-lg p-4 min-w-64">
              <label for="radius-slider" class="block text-sm font-medium text-gray-700 mb-2">
                Search Radius: <span class="font-bold">{@radius_km}km</span>
              </label>
              <input
                id="radius-slider"
                type="range"
                min="5"
                max="100"
                step="5"
                value={@radius_km}
                phx-change="change_radius"
                phx-debounce="500"
                class="w-full h-2 bg-gray-300 rounded-lg appearance-none cursor-pointer"
                name="radius"
              />
              <div class="flex justify-between text-xs mt-1 text-gray-500">
                <span>5km</span>
                <span>50km</span>
                <span>100km</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Events Grid using the same component as Activities -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div :if={@loading} class="flex justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
        </div>

        <%= if not @loading and @events == [] do %>
          <div class="text-center py-12">
            <Heroicons.calendar_days class="mx-auto h-12 w-12 text-gray-400" />
            <h3 class="mt-2 text-lg font-medium text-gray-900">
              No events found
            </h3>
            <p class="mt-1 text-sm text-gray-500">
              No upcoming events within {@radius_km}km of {@city.name}.
            </p>
            <p class="mt-1 text-sm text-gray-500">
              Try increasing the search radius or check back later.
            </p>
          </div>
        <% else %>
          <div :if={not @loading} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <.event_card :for={event <- @events} event={event} language="en" />
          </div>
        <% end %>
      </div>

      <!-- Nearby Cities -->
      <div :if={@nearby_cities != [] and @nearby_cities != nil} class="bg-gray-100 border-t">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <h2 class="text-2xl font-bold text-gray-900 mb-6">
            Explore Nearby Cities
          </h2>
          <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <.link
              :for={nearby_city <- @nearby_cities}
              :if={nearby_city.id != @city.id}
              navigate={~p"/c/#{nearby_city.slug}"}
              class="bg-white rounded-lg p-4 hover:shadow-md transition group"
            >
              <h3 class="font-semibold text-gray-900 group-hover:text-blue-600">
                {nearby_city.name}
              </h3>
              <p class="text-sm text-gray-500">
                {nearby_city.country.name}
              </p>
              <p class="text-xs text-gray-400 mt-1">
                <%= calculate_distance_text(@city, nearby_city) %>
              </p>
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Using the exact same event_card component from PublicEventsIndexLive
  defp event_card(assigns) do
    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block">
      <div class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow">
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
            <% category = List.first(@event.categories) %>
            <%= if category && category.color do %>
              <div
                class="absolute top-3 left-3 px-2 py-1 rounded-md text-xs font-medium text-white"
                style={"background-color: #{category.color}"}
              >
                <%= category.name %>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Event Details -->
        <div class="p-4">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-2">
            <%= Map.get(@event, :display_title, @event.title) %>
          </h3>

          <div class="mt-2 flex items-center text-sm text-gray-600">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= format_datetime(@event.starts_at) %>
          </div>

          <%= if @event.venue do %>
            <div class="mt-1 flex items-center text-sm text-gray-600">
              <Heroicons.map_pin class="w-4 h-4 mr-1" />
              <%= @event.venue.name %>
            </div>
          <% end %>

          <%= if @event.min_price || @event.max_price do %>
            <div class="mt-2">
              <span class="text-sm font-medium text-gray-900">
                <%= format_price_range(@event) %>
              </span>
            </div>
          <% else %>
            <div class="mt-2">
              <span class="text-sm font-medium text-green-600">
                Free
              </span>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # Private functions

  defp fetch_events(socket) do
    %{city: city, radius_km: radius_km} = socket.assigns

    events = Locations.get_city_events(city,
      radius_km: radius_km,
      limit: 50,
      upcoming_only: true
    )

    socket
    |> assign(:events, events)
    |> assign(:loading, false)
  end

  defp fetch_nearby_cities(socket) do
    %{city: city} = socket.assigns

    nearby_cities =
      if city.latitude && city.longitude do
        Locations.get_nearby_cities(
          Decimal.to_float(city.latitude),
          Decimal.to_float(city.longitude),
          radius_km: 50,
          limit: 8
        )
      else
        []
      end

    assign(socket, :nearby_cities, nearby_cities)
  end

  defp parse_radius(nil), do: @default_radius_km
  defp parse_radius(radius_str) do
    case Integer.parse(radius_str) do
      {radius, _} when radius >= @min_radius_km and radius <= @max_radius_km ->
        radius
      _ ->
        @default_radius_km
    end
  end

  defp page_title(city) do
    "Events in #{city.name}, #{city.country.name} | Eventasaurus"
  end

  defp meta_description(city) do
    "Discover upcoming events in #{city.name}, #{city.country.name}. Find concerts, festivals, workshops, and more happening near you."
  end

  defp format_datetime(nil), do: "TBD"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  defp format_price_range(event) do
    cond do
      event.min_price && event.max_price && event.min_price == event.max_price ->
        "$#{event.min_price}"

      event.min_price && event.max_price ->
        "$#{event.min_price} - $#{event.max_price}"

      event.min_price ->
        "From $#{event.min_price}"

      event.max_price ->
        "Up to $#{event.max_price}"

      true ->
        "Free"
    end
  end

  defp calculate_distance_text(city1, city2) do
    if city1.latitude && city1.longitude && city2.latitude && city2.longitude do
      distance = Locations.calculate_distance(
        Decimal.to_float(city1.latitude),
        Decimal.to_float(city1.longitude),
        Decimal.to_float(city2.latitude),
        Decimal.to_float(city2.longitude)
      )

      if distance do
        "~#{round(distance)} km away"
      else
        ""
      end
    else
      ""
    end
  end
end