defmodule EventasaurusWeb.VenueLive.Show do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Events.Event
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:venue, nil)
      |> assign(:loading, true)
      |> assign(:upcoming_events, [])
      |> assign(:past_events, [])
      |> assign(:show_past_events, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _url, socket) do
    # Handle both direct venue slug and city-scoped venue slug
    venue = get_venue_by_slug(slug, params["city_slug"])

    case venue do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Venue not found"))
         |> push_navigate(to: ~p"/")}

      venue ->
        # Preload city and country
        venue = Repo.preload(venue, city_ref: :country)

        # Get events for this venue
        events = get_venue_events(venue.id)

        socket =
          socket
          |> assign(:venue, venue)
          |> assign(:upcoming_events, events.upcoming)
          |> assign(:past_events, events.past)
          |> assign(:loading, false)
          |> assign(:page_title, venue.name)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_past_events", _params, socket) do
    {:noreply, assign(socket, :show_past_events, !socket.assigns.show_past_events)}
  end

  # Helper functions

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

    upcoming =
      from(e in Event,
        where: e.venue_id == ^venue_id,
        where: e.start_at >= ^now,
        order_by: [asc: e.start_at],
        limit: 20
      )
      |> Repo.all()

    past =
      from(e in Event,
        where: e.venue_id == ^venue_id,
        where: e.start_at < ^now,
        order_by: [desc: e.start_at],
        limit: 20
      )
      |> Repo.all()

    %{upcoming: upcoming, past: past}
  end

  defp format_date(nil), do: gettext("Unknown")

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end

  defp format_date(%Date{} = date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <%= if @loading do %>
        <div class="flex items-center justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
      <% else %>
        <div class="bg-white shadow-sm rounded-lg overflow-hidden">
          <!-- Venue Header -->
          <div class="bg-gradient-to-r from-indigo-600 to-purple-600 px-6 py-8 text-white">
            <h1 class="text-3xl font-bold mb-2"><%= @venue.name %></h1>
            <%= if @venue.city_ref do %>
              <p class="text-indigo-100">
                <%= @venue.city_ref.name %><%= if @venue.city_ref.country, do: ", #{@venue.city_ref.country.name}", else: "" %>
              </p>
            <% end %>
          </div>

          <!-- Venue Details -->
          <div class="px-6 py-6 border-b border-gray-200">
            <%= if @venue.address do %>
              <div class="mb-4">
                <h3 class="text-sm font-medium text-gray-500 uppercase tracking-wide">Address</h3>
                <p class="mt-1 text-gray-900"><%= @venue.address %></p>
              </div>
            <% end %>

            <%= if @venue.latitude && @venue.longitude do %>
              <div class="mb-4">
                <h3 class="text-sm font-medium text-gray-500 uppercase tracking-wide">Location</h3>
                <p class="mt-1 text-gray-900"><%= @venue.latitude %>, <%= @venue.longitude %></p>
              </div>
            <% end %>
          </div>

          <!-- Upcoming Events -->
          <div class="px-6 py-6">
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Upcoming Events</h2>
            <%= if Enum.empty?(@upcoming_events) do %>
              <p class="text-gray-500">No upcoming events scheduled.</p>
            <% else %>
              <div class="space-y-4">
                <%= for event <- @upcoming_events do %>
                  <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow">
                    <h3 class="text-lg font-semibold text-gray-900">
                      <%= event.title %>
                    </h3>
                    <p class="text-sm text-gray-500 mt-1">
                      <%= format_date(event.start_at) %>
                    </p>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <!-- Past Events (Collapsible) -->
          <%= if !Enum.empty?(@past_events) do %>
            <div class="px-6 py-6 border-t border-gray-200">
              <button
                type="button"
                phx-click="toggle_past_events"
                class="flex items-center justify-between w-full text-left"
              >
                <h2 class="text-2xl font-bold text-gray-900">Past Events</h2>
                <svg
                  class={"w-6 h-6 transform transition-transform #{if @show_past_events, do: "rotate-180", else: ""}"}
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </button>

              <%= if @show_past_events do %>
                <div class="mt-4 space-y-4">
                  <%= for event <- @past_events do %>
                    <div class="border border-gray-200 rounded-lg p-4 opacity-75">
                      <h3 class="text-lg font-semibold text-gray-900">
                        <%= event.title %>
                      </h3>
                      <p class="text-sm text-gray-500 mt-1">
                        <%= format_date(event.start_at) %>
                      </p>
                    </div>
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
