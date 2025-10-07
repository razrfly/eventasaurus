defmodule EventasaurusWeb.PerformerLive.Show do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Performers.PerformerStore
  alias EventasaurusWeb.Components.CountryFlag

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:performer, nil)
      |> assign(:loading, true)
      |> assign(:stats, %{})
      |> assign(:upcoming_events, [])
      |> assign(:past_events, [])
      |> assign(:show_past_events, false)
      |> assign(:past_events_page, 1)
      |> assign(:past_events_per_page, 10)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _url, socket) do
    case PerformerStore.get_performer_by_slug(slug) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Performer not found"))
         |> push_navigate(to: ~p"/")}

      performer ->
        # Get stats and events
        stats = PerformerStore.get_performer_stats(performer.id)
        events = PerformerStore.get_performer_events(performer.id)

        socket =
          socket
          |> assign(:performer, performer)
          |> assign(:stats, stats)
          |> assign(:upcoming_events, events.upcoming)
          |> assign(:past_events, events.past)
          |> assign(:loading, false)
          |> assign(:page_title, performer.name)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_past_events", _params, socket) do
    {:noreply, assign(socket, :show_past_events, !socket.assigns.show_past_events)}
  end

  @impl true
  def handle_event("load_more_past", _params, socket) do
    {:noreply, update(socket, :past_events_page, &(&1 + 1))}
  end

  # Helper functions

  defp ra_artist_url(performer) do
    get_in(performer.metadata, ["ra_artist_url"])
  end

  defp performer_country(performer) do
    get_in(performer.metadata, ["country"])
  end

  defp performer_country_code(performer) do
    get_in(performer.metadata, ["country_code"])
  end

  defp performer_source(performer) do
    get_in(performer.metadata, ["source"]) || "unknown"
  end

  defp format_date(nil), do: gettext("Unknown")

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  defp format_date(%Date{} = date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp paginated_past_events(past_events, page, per_page) do
    past_events
    |> Enum.reverse()
    |> Enum.take(page * per_page)
  end

  defp has_more_past_events?(past_events, page, per_page) do
    length(past_events) > page * per_page
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= if @loading do %>
        <div class="flex justify-center items-center min-h-screen">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
      <% else %>
        <div class="max-w-6xl mx-auto px-4 py-8">
          <!-- Performer Header -->
          <div class="bg-white rounded-lg shadow-md p-8 mb-8">
            <div class="flex flex-col md:flex-row gap-6 items-start">
              <!-- Performer Image -->
              <div class="flex-shrink-0">
                <%= if @performer.image_url do %>
                  <img
                    src={@performer.image_url}
                    alt={@performer.name}
                    class="w-48 h-48 rounded-lg object-cover shadow-lg"
                  />
                <% else %>
                  <div class="w-48 h-48 rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center shadow-lg">
                    <span class="text-6xl text-white font-bold">
                      <%= String.first(@performer.name) %>
                    </span>
                  </div>
                <% end %>
              </div>

              <!-- Performer Info -->
              <div class="flex-1">
                <div class="flex items-center gap-3 mb-2">
                  <h1 class="text-4xl font-bold text-gray-900">
                    <%= @performer.name %>
                  </h1>
                  <%= if performer_country_code(@performer) do %>
                    <CountryFlag.flag country_code={performer_country_code(@performer)} size="lg" />
                  <% end %>
                </div>

                <%= if performer_country(@performer) do %>
                  <p class="text-lg text-gray-600 mb-4">
                    <span class="inline-flex items-center">
                      <svg
                        class="w-5 h-5 mr-2"
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
                      <%= performer_country(@performer) %>
                    </span>
                  </p>
                <% end %>

                <!-- External Links -->
                <div class="flex gap-3 mt-4">
                  <%= if ra_artist_url(@performer) do %>
                    <a
                      href={ra_artist_url(@performer)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-flex items-center px-4 py-2 bg-black text-white rounded-lg hover:bg-gray-800 transition-colors"
                    >
                      <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M12 2L2 7v10c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-10-5z" />
                      </svg>
                      Resident Advisor
                    </a>
                  <% end %>
                </div>

                <!-- Source Attribution -->
                <p class="text-sm text-gray-500 mt-4">
                  <%= gettext("Data source") %>: <%= performer_source(@performer) %>
                </p>
              </div>
            </div>
          </div>

          <!-- Quick Stats Bar -->
          <div class="bg-white rounded-lg shadow-md p-6 mb-8">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div class="text-center">
                <div class="text-3xl font-bold text-indigo-600">
                  <%= @stats.total_events %>
                </div>
                <div class="text-sm text-gray-600 mt-1">
                  <%= gettext("Total Events") %>
                </div>
              </div>

              <div class="text-center">
                <div class="text-xl font-semibold text-gray-800">
                  <%= format_date(@stats.first_event) %>
                </div>
                <div class="text-sm text-gray-600 mt-1">
                  <%= gettext("First Event") %>
                </div>
              </div>

              <div class="text-center">
                <div class="text-xl font-semibold text-gray-800">
                  <%= format_date(@stats.latest_event) %>
                </div>
                <div class="text-sm text-gray-600 mt-1">
                  <%= gettext("Latest Event") %>
                </div>
              </div>
            </div>
          </div>

          <!-- Upcoming Events -->
          <div class="bg-white rounded-lg shadow-md p-8 mb-8">
            <h2 class="text-2xl font-bold text-gray-900 mb-6">
              <%= gettext("Upcoming Events") %>
            </h2>

            <%= if Enum.empty?(@upcoming_events) do %>
              <p class="text-gray-600 text-center py-8">
                <%= gettext("No upcoming events scheduled") %>
              </p>
            <% else %>
              <div class="space-y-4">
                <%= for event <- Enum.take(@upcoming_events, 10) do %>
                  <a
                    href={~p"/activities/#{event.slug}"}
                    class="block p-4 border border-gray-200 rounded-lg hover:border-indigo-500 hover:shadow-md transition-all"
                  >
                    <div class="flex justify-between items-start">
                      <div class="flex-1">
                        <h3 class="text-lg font-semibold text-gray-900 mb-1">
                          <%= event.title %>
                        </h3>
                        <%= if event.venue && event.venue.city_ref do %>
                          <p class="text-sm text-gray-600">
                            <%= event.venue.city_ref.name %>
                          </p>
                        <% end %>
                      </div>
                      <div class="text-right ml-4">
                        <div class="text-sm font-medium text-indigo-600">
                          <%= format_date(event.starts_at) %>
                        </div>
                      </div>
                    </div>
                  </a>
                <% end %>
              </div>
            <% end %>
          </div>

          <!-- Past Events (Collapsible) -->
          <%= if not Enum.empty?(@past_events) do %>
            <div class="bg-white rounded-lg shadow-md p-8">
              <button
                phx-click="toggle_past_events"
                class="w-full flex justify-between items-center text-left"
              >
                <h2 class="text-2xl font-bold text-gray-900">
                  <%= gettext("Past Events") %> (<%= length(@past_events) %>)
                </h2>
                <svg
                  class={"w-6 h-6 transition-transform #{if @show_past_events, do: "rotate-180", else: ""}"}
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
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
                <div class="mt-6 space-y-4">
                  <%= for event <- paginated_past_events(@past_events, @past_events_page, @past_events_per_page) do %>
                    <a
                      href={~p"/activities/#{event.slug}"}
                      class="block p-4 border border-gray-200 rounded-lg hover:border-indigo-500 hover:shadow-md transition-all"
                    >
                      <div class="flex justify-between items-start">
                        <div class="flex-1">
                          <h3 class="text-lg font-semibold text-gray-900 mb-1">
                            <%= event.title %>
                          </h3>
                          <%= if event.venue && event.venue.city_ref do %>
                            <p class="text-sm text-gray-600">
                              <%= event.venue.city_ref.name %>
                            </p>
                          <% end %>
                        </div>
                        <div class="text-right ml-4">
                          <div class="text-sm font-medium text-gray-500">
                            <%= format_date(event.starts_at) %>
                          </div>
                        </div>
                      </div>
                    </a>
                  <% end %>

                  <%= if has_more_past_events?(@past_events, @past_events_page, @past_events_per_page) do %>
                    <button
                      phx-click="load_more_past"
                      class="w-full py-3 px-4 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors font-medium"
                    >
                      <%= gettext("Load More") %>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
