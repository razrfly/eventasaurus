defmodule EventasaurusWeb.PerformerLive.Show do
  @moduledoc """
  LiveView for displaying performer/artist detail pages.

  Shows performer information using the PerformerHeroCard component
  and displays upcoming/past events using EventCards for consistency
  with city and venue pages.

  Uses ActivityLayout for consistent two-column responsive layout
  matching venue and activity pages.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Performers.PerformerStore

  alias EventasaurusWeb.Components.{
    Breadcrumbs,
    EventCards
  }

  alias EventasaurusWeb.Components.Activity.{
    ActivityLayout,
    PerformerHeroCard
  }

  alias EventasaurusWeb.Helpers.BreadcrumbBuilder

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
      |> assign(:past_events_per_page, 12)
      |> assign(:breadcrumb_items, [])

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

        # Build breadcrumb items
        breadcrumb_items =
          BreadcrumbBuilder.build_performer_breadcrumbs(performer,
            gettext_backend: EventasaurusWeb.Gettext
          )

        socket =
          socket
          |> assign(:performer, performer)
          |> assign(:stats, stats)
          |> assign(:upcoming_events, events.upcoming)
          |> assign(:past_events, events.past)
          |> assign(:loading, false)
          |> assign(:page_title, performer.name)
          |> assign(:breadcrumb_items, breadcrumb_items)

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
    <div class="min-h-screen">
      <%= if @loading do %>
        <div class="flex justify-center items-center min-h-screen">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
      <% else %>
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <!-- Breadcrumbs -->
          <Breadcrumbs.breadcrumb items={@breadcrumb_items} class="mb-6" />

          <ActivityLayout.activity_layout>
            <:main>
              <!-- Performer Hero Card -->
              <PerformerHeroCard.performer_hero_card
                performer={@performer}
                upcoming_event_count={length(@upcoming_events)}
                total_event_count={@stats.total_events}
              />

              <!-- Upcoming Events Section -->
              <div>
                <h2 class="text-2xl font-bold text-gray-900 mb-6">
                  <%= gettext("Upcoming Events") %>
                </h2>

                <%= if Enum.empty?(@upcoming_events) do %>
                  <div class="bg-white rounded-lg shadow-md p-8 text-center">
                    <Heroicons.calendar class="w-12 h-12 mx-auto text-gray-400 mb-4" />
                    <p class="text-gray-600">
                      <%= gettext("No upcoming events scheduled") %>
                    </p>
                  </div>
                <% else %>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <%= for event <- Enum.take(@upcoming_events, 12) do %>
                      <EventCards.event_card event={event} show_city={true} />
                    <% end %>
                  </div>

                  <%= if length(@upcoming_events) > 12 do %>
                    <div class="mt-6 text-center">
                      <p class="text-sm text-gray-500">
                        <%= gettext("Showing %{shown} of %{total} upcoming events",
                          shown: min(12, length(@upcoming_events)),
                          total: length(@upcoming_events)
                        ) %>
                      </p>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <!-- Past Events (Collapsible) -->
              <%= if not Enum.empty?(@past_events) do %>
                <div class="bg-white rounded-lg shadow-md overflow-hidden">
                  <button
                    phx-click="toggle_past_events"
                    class="w-full flex justify-between items-center text-left p-6 hover:bg-gray-50 transition-colors"
                  >
                    <h2 class="text-2xl font-bold text-gray-900">
                      <%= gettext("Past Events") %>
                      <span class="text-lg font-normal text-gray-500 ml-2">
                        (<%= length(@past_events) %>)
                      </span>
                    </h2>
                    <Heroicons.chevron_down class={"w-6 h-6 text-gray-500 transition-transform duration-200 #{if @show_past_events, do: "rotate-180", else: ""}"} />
                  </button>

                  <%= if @show_past_events do %>
                    <div class="border-t border-gray-200 p-6">
                      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                        <%= for event <- paginated_past_events(@past_events, @past_events_page, @past_events_per_page) do %>
                          <EventCards.event_card event={event} show_city={true} />
                        <% end %>
                      </div>

                      <%= if has_more_past_events?(@past_events, @past_events_page, @past_events_per_page) do %>
                        <div class="mt-6 text-center">
                          <button
                            phx-click="load_more_past"
                            class="inline-flex items-center px-6 py-3 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors font-medium"
                          >
                            <Heroicons.arrow_down class="w-5 h-5 mr-2" />
                            <%= gettext("Load More") %>
                          </button>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </:main>

            <:sidebar>
              <!-- Performer Stats Card -->
              <div class="bg-white rounded-lg shadow-md p-6">
                <h3 class="text-lg font-semibold text-gray-900 mb-4">
                  <%= gettext("Artist Stats") %>
                </h3>
                <div class="space-y-3">
                  <div class="flex justify-between items-center">
                    <span class="text-gray-600"><%= gettext("Upcoming Events") %></span>
                    <span class="font-semibold text-gray-900"><%= length(@upcoming_events) %></span>
                  </div>
                  <div class="flex justify-between items-center">
                    <span class="text-gray-600"><%= gettext("Past Events") %></span>
                    <span class="font-semibold text-gray-900"><%= length(@past_events) %></span>
                  </div>
                  <div class="flex justify-between items-center">
                    <span class="text-gray-600"><%= gettext("Total Events") %></span>
                    <span class="font-semibold text-gray-900"><%= @stats.total_events %></span>
                  </div>
                </div>
              </div>

              <!-- External Links Card (if RA URL exists) -->
              <%= if get_ra_url(@performer) do %>
                <div class="bg-white rounded-lg shadow-md p-6">
                  <h3 class="text-lg font-semibold text-gray-900 mb-4">
                    <%= gettext("External Links") %>
                  </h3>
                  <a
                    href={get_ra_url(@performer)}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="inline-flex items-center text-indigo-600 hover:text-indigo-800 font-medium"
                  >
                    <Heroicons.arrow_top_right_on_square class="w-5 h-5 mr-2" />
                    <%= gettext("Resident Advisor") %>
                  </a>
                </div>
              <% end %>
            </:sidebar>
          </ActivityLayout.activity_layout>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper to extract RA URL from performer metadata
  defp get_ra_url(%{metadata: %{"ra_artist_url" => url}}) when is_binary(url), do: url
  defp get_ra_url(_), do: nil
end
