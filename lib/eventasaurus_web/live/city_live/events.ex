defmodule EventasaurusWeb.CityLive.Events do
  @moduledoc """
  LiveView for container type index pages (all festivals, conferences, etc. in a city).

  Displays all containers of a specific type within a city.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEvents.{PublicEventContainers, PublicEventContainer}
  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
  alias EventasaurusWeb.Components.Breadcrumbs

  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
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
         |> assign(:language, language)
         |> assign(:container_type, nil)
         |> assign(:containers, [])
         |> assign(:loading, true)}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket = load_containers(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_language", %{"language" => language}, socket) do
    socket =
      socket
      |> assign(:language, language)
      |> Phoenix.LiveView.push_event("set_language_cookie", %{language: language})

    {:noreply, socket}
  end

  defp load_containers(socket) do
    city = socket.assigns.city
    container_type = get_container_type_from_live_action(socket)

    # Use efficient query with city filtering and counts at DB level
    containers =
      PublicEventContainers.list_containers(
        type: container_type,
        city_id: city.id,
        with_counts: true
      )

    type_label = container_type_label(container_type)
    type_plural = PublicEventContainer.container_type_plural(container_type)

    # Build breadcrumb items using BreadcrumbBuilder
    breadcrumb_items =
      BreadcrumbBuilder.build_container_type_index_breadcrumbs(city, container_type)

    socket
    |> assign(:container_type, container_type)
    |> assign(:containers, containers)
    |> assign(:loading, false)
    |> assign(:page_title, "#{type_plural |> String.capitalize()} in #{city.name}")
    |> assign(:type_label, type_label)
    |> assign(:type_plural, type_plural)
    |> assign(:breadcrumb_items, breadcrumb_items)
  end

  defp get_container_type_from_live_action(socket) do
    case socket.assigns.live_action do
      :festivals -> :festival
      :conferences -> :conference
      :tours -> :tour
      :series -> :series
      :exhibitions -> :exhibition
      :tournaments -> :tournament
      _ -> :festival
    end
  end

  defp container_type_label(:festival), do: "Festival"
  defp container_type_label(:conference), do: "Conference"
  defp container_type_label(:tour), do: "Tour"
  defp container_type_label(:series), do: "Series"
  defp container_type_label(:exhibition), do: "Exhibition"
  defp container_type_label(:tournament), do: "Tournament"
  defp container_type_label(_), do: "Event"

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
            <Breadcrumbs.breadcrumb items={@breadcrumb_items} class="mb-4" />

            <div class="flex items-start justify-between">
              <div class="flex-1">
                <h1 class="text-4xl font-bold text-gray-900">
                  <%= String.capitalize(@type_plural) %> in <%= @city.name %>
                </h1>

                <div class="flex items-center gap-4 mt-4 text-gray-600">
                  <div class="flex items-center">
                    <Heroicons.map_pin class="w-5 h-5 mr-2" />
                    <span><%= @city.name %></span>
                  </div>

                  <div class="flex items-center">
                    <Heroicons.calendar class="w-5 h-5 mr-2" />
                    <span><%= length(@containers) %> <%= if length(@containers) == 1, do: String.downcase(@type_label), else: String.downcase(@type_plural) %></span>
                  </div>
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

        <!-- Containers Grid -->
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <%= if @containers == [] do %>
            <div class="text-center py-12">
              <Heroicons.calendar_days class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-lg font-medium text-gray-900">
                No <%= String.downcase(@type_plural) %> found
              </h3>
              <p class="mt-1 text-sm text-gray-500">
                There are no <%= String.downcase(@type_plural) %> in <%= @city.name %> at the moment.
              </p>
              <div class="mt-6">
                <.link
                  navigate={~p"/c/#{@city.slug}"}
                  class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  Browse all events
                </.link>
              </div>
            </div>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for container <- @containers do %>
                <%= container_card_wrapper(assigns, container) %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>

    <div id="language-cookie-hook" phx-hook="LanguageCookie"></div>
    """
  end

  defp container_card_wrapper(assigns, container) do
    assigns = assign(assigns, :container, container)

    ~H"""
    <.link navigate={"/c/#{@city.slug}/#{PublicEventContainer.container_type_plural(@container.container_type)}/#{@container.slug}"} class="block">
      <div class="bg-white rounded-lg shadow hover:shadow-md transition-shadow overflow-hidden">
        <!-- Container Image/Placeholder -->
        <div class="w-full h-48 bg-gradient-to-br from-purple-100 to-blue-100 flex items-center justify-center">
          <div class="text-center">
            <Heroicons.calendar_days class="w-16 h-16 text-purple-500 mx-auto" />
            <div class={"mt-2 px-3 py-1 rounded-md text-sm font-medium text-white #{get_badge_color(@container.container_type)} inline-block"}>
              <%= container_type_label(@container.container_type) %>
            </div>
          </div>
        </div>

        <!-- Container Info -->
        <div class="p-6">
          <h3 class="text-xl font-semibold text-gray-900 mb-2">
            <%= @container.title %>
          </h3>

          <div class="space-y-2 text-sm text-gray-600">
            <div class="flex items-center">
              <Heroicons.calendar class="w-4 h-4 mr-2" />
              <span><%= format_date_range(@container) %></span>
            </div>

            <div class="flex items-center">
              <Heroicons.ticket class="w-4 h-4 mr-2" />
              <span><%= count_container_events(@container) %> events</span>
            </div>

            <%= if @container.description do %>
              <p class="mt-3 text-gray-600 line-clamp-2">
                <%= @container.description %>
              </p>
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp get_badge_color(:festival), do: "bg-purple-500"
  defp get_badge_color(:conference), do: "bg-orange-500"
  defp get_badge_color(:tour), do: "bg-red-500"
  defp get_badge_color(:series), do: "bg-indigo-500"
  defp get_badge_color(:exhibition), do: "bg-yellow-500"
  defp get_badge_color(:tournament), do: "bg-pink-500"
  defp get_badge_color(_), do: "bg-gray-500"

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

  defp count_container_events(container) do
    # Use preloaded event_count from query for efficiency
    Map.get(container, :event_count, 0)
  end
end
