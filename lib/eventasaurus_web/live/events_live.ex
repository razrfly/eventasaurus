defmodule EventasaurusWeb.EventsLive do
  use EventasaurusWeb, :live_view
  alias EventasaurusApp.Events

  @impl true
  def mount(_params, _session, socket) do
    events = Events.list_public_events()
    
    {:ok,
     socket
     |> assign(:page_title, "Browse Events")
     |> assign(:events, events)
     |> assign(:search, "")
     |> assign(:searching, false)}
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    send(self(), {:do_search, search_term})
    
    {:noreply,
     socket
     |> assign(:search, search_term)
     |> assign(:searching, true)}
  end

  @impl true
  def handle_info({:do_search, search_term}, socket) do
    events = Events.list_public_events(search: search_term)
    
    {:noreply,
     socket
     |> assign(:events, events)
     |> assign(:searching, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%!-- Header --%>
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Discover Events</h1>
          <p class="mt-2 text-gray-600">Find and join real gatherings in your community</p>
        </div>

        <%!-- Search Bar --%>
        <div class="mb-8">
          <form phx-change="search" class="relative">
            <div class="relative">
              <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <svg class="h-5 w-5 text-gray-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clip-rule="evenodd" />
                </svg>
              </div>
              <input
                type="text"
                name="search"
                value={@search}
                placeholder="Search events by title or description..."
                class="block w-full pl-10 pr-3 py-3 border border-gray-300 rounded-lg leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                phx-debounce="300"
              />
              <%= if @searching do %>
                <div class="absolute inset-y-0 right-0 pr-3 flex items-center">
                  <svg class="animate-spin h-5 w-5 text-gray-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                </div>
              <% end %>
            </div>
          </form>
        </div>

        <%!-- Events Grid --%>
        <%= if @events == [] do %>
          <div class="text-center py-12">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No events found</h3>
            <p class="mt-1 text-sm text-gray-500">
              <%= if @search != "" do %>
                Try adjusting your search terms
              <% else %>
                Check back soon for upcoming events
              <% end %>
            </p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <%= for event <- @events do %>
              <a
                href={~p"/#{event.slug}"}
                class="group relative bg-white rounded-lg shadow-sm hover:shadow-lg transition-shadow duration-200 overflow-hidden"
              >
                <%!-- Event Image --%>
                <div class="aspect-w-16 aspect-h-9 bg-gray-200">
                  <% image_url = event.cover_image_url || get_external_image_url(event.external_image_data) %>
                  <%= if image_url do %>
                    <img
                      src={image_url}
                      alt={event.title}
                      class="object-cover w-full h-48"
                    />
                  <% else %>
                    <div class="flex items-center justify-center h-48 bg-gradient-to-br from-blue-500 to-purple-600">
                      <svg class="h-16 w-16 text-white opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                      </svg>
                    </div>
                  <% end %>
                </div>

                <%!-- Event Details --%>
                <div class="p-6">
                  <%!-- Status Badge --%>
                  <%= if event.status != :confirmed do %>
                    <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium mb-2 " <> status_badge_class(event.status)}>
                      <%= format_status(event.status) %>
                    </span>
                  <% end %>

                  <%!-- Title --%>
                  <h3 class="text-lg font-semibold text-gray-900 group-hover:text-blue-600 mb-2">
                    <%= event.title %>
                  </h3>

                  <%!-- Tagline --%>
                  <%= if event.tagline do %>
                    <p class="text-sm text-gray-600 mb-3 line-clamp-2">
                      <%= event.tagline %>
                    </p>
                  <% end %>

                  <%!-- Date and Time --%>
                  <div class="flex items-center text-sm text-gray-500 mb-2">
                    <svg class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    <%= format_event_date(event.start_at, event.timezone) %>
                  </div>

                  <%!-- Location --%>
                  <%= if event.venue do %>
                    <div class="flex items-center text-sm text-gray-500">
                      <svg class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                      </svg>
                      <%= event.venue.name %>
                    </div>
                  <% else %>
                    <%= if event.is_virtual do %>
                      <div class="flex items-center text-sm text-gray-500">
                        <svg class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
                        </svg>
                        Virtual Event
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </a>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions
  defp get_external_image_url(%{"url" => url}), do: url
  defp get_external_image_url(_), do: nil

  defp status_badge_class(:draft), do: "bg-gray-100 text-gray-800"
  defp status_badge_class(:polling), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(:threshold), do: "bg-blue-100 text-blue-800"
  defp status_badge_class(:canceled), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-green-100 text-green-800"

  defp format_status(:draft), do: "Draft"
  defp format_status(:polling), do: "Polling"
  defp format_status(:threshold), do: "Pre-sale"
  defp format_status(:canceled), do: "Canceled"
  defp format_status(_), do: "Confirmed"

  defp format_event_date(nil, _timezone), do: "Date TBD"
  defp format_event_date(datetime, timezone) do
    # Convert to the event's timezone if specified
    datetime = if timezone do
      case DateTime.shift_zone(datetime, timezone) do
        {:ok, shifted} -> shifted
        _ -> datetime
      end
    else
      datetime
    end

    # Format as "Jan 15, 2024 at 7:00 PM"
    month = Calendar.strftime(datetime, "%b")
    day = Calendar.strftime(datetime, "%d")
    year = Calendar.strftime(datetime, "%Y")
    hour = datetime.hour
    minute = Calendar.strftime(datetime, "%M")
    period = if hour >= 12, do: "PM", else: "AM"
    hour_12 = case hour do
      0 -> 12
      h when h > 12 -> h - 12
      h -> h
    end
    
    "#{month} #{day}, #{year} at #{hour_12}:#{minute} #{period}"
  end
end