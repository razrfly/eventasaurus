defmodule EventasaurusWeb.VenuesIndexLive do
  @moduledoc """
  Venues index page showing all public venues.

  Issue #3143: Part of the simplified venue routing structure.
  Issue #3294: Uses keyset pagination to avoid O(n) OFFSET scans.
  Routes: /venues
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Pagination
  alias EventasaurusWeb.Helpers.SEOHelpers

  import Ecto.Query

  @default_page_size 30

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Venues")
      |> assign(:venues, [])
      |> assign(:loading, true)
      |> assign(:search, nil)
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> assign(:total_entries, 0)

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _url, socket) do
    cursor = params["cursor"]
    search = params["search"]

    result = load_venues(cursor, search)

    socket =
      socket
      |> assign(:venues, result.entries)
      |> assign(:search, search)
      |> assign(:cursor, result.cursor)
      |> assign(:has_more, result.has_more?)
      |> assign(:total_entries, result.total_entries)
      |> assign(:loading, false)
      |> SEOHelpers.assign_meta_tags(
        title: "Venues",
        description:
          "Discover venues hosting events near you. Find concert halls, theaters, clubs, and more.",
        canonical_path: "/venues"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    # Reset to first page when searching
    {:noreply, push_patch(socket, to: build_path(search))}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply, push_patch(socket, to: "/venues")}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    # Load next page and APPEND to existing venues (true "Load More" UX)
    result = load_venues(socket.assigns.cursor, socket.assigns.search)

    socket =
      socket
      |> assign(:venues, socket.assigns.venues ++ result.entries)
      |> assign(:cursor, result.cursor)
      |> assign(:has_more, result.has_more?)

    {:noreply, socket}
  end

  defp load_venues(cursor, search) do
    # Base query without ordering (keyset pagination adds its own)
    base_query =
      from(v in Venue,
        left_join: c in assoc(v, :city_ref),
        where: v.is_public == true,
        where: not is_nil(v.slug),
        preload: [city_ref: c]
      )

    query =
      if search && search != "" do
        search_term = "%#{search}%"

        from(v in base_query,
          where: ilike(v.name, ^search_term) or ilike(v.address, ^search_term)
        )
      else
        base_query
      end

    # Use keyset pagination (O(1) vs O(n) for OFFSET)
    result =
      Pagination.paginate_keyset(query, Repo,
        cursor: cursor,
        page_size: @default_page_size,
        sort_field: :name,
        sort_dir: :asc
      )

    # Batch load event counts to avoid N+1 queries
    venue_ids = Enum.map(result.entries, & &1.id)
    event_counts = batch_count_venue_events(venue_ids)

    # Merge event counts into venues
    venues =
      Enum.map(result.entries, fn venue ->
        count = Map.get(event_counts, venue.id, 0)
        Map.put(venue, :upcoming_event_count, count)
      end)

    %{result | entries: venues}
  end

  # Batch count upcoming events for multiple venues in a single query
  # Returns a map of %{venue_id => count}
  @spec batch_count_venue_events([integer()]) :: %{integer() => integer()}
  defp batch_count_venue_events([]), do: %{}

  defp batch_count_venue_events(venue_ids) do
    now = DateTime.utc_now()

    from(pe in PublicEvent,
      where: pe.venue_id in ^venue_ids,
      where:
        (not is_nil(pe.ends_at) and pe.ends_at > ^now) or
          (is_nil(pe.ends_at) and pe.starts_at > ^now),
      group_by: pe.venue_id,
      select: {pe.venue_id, count(pe.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp build_path(search) do
    # Note: cursor is not included in URL - "Load More" appends client-side
    # Only search affects the URL for bookmarking/sharing
    if search && search != "" do
      "/venues?#{URI.encode_query(%{"search" => search})}"
    else
      "/venues"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Venues</h1>
          <p class="mt-2 text-gray-600">
            Discover venues hosting events near you
          </p>
        </div>

        <!-- Search -->
        <div class="mb-6">
          <form phx-submit="search" class="flex gap-4">
            <div class="flex-1">
              <input
                type="text"
                name="search"
                value={@search}
                placeholder="Search venues by name or location..."
                class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
              />
            </div>
            <button
              type="submit"
              class="px-6 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors"
            >
              Search
            </button>
            <%= if @search do %>
              <button
                type="button"
                phx-click="clear_search"
                class="px-4 py-2 text-gray-600 hover:text-gray-800 transition-colors"
              >
                Clear
              </button>
            <% end %>
          </form>
        </div>

        <%= if @loading do %>
          <div class="flex justify-center py-12">
            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600"></div>
          </div>
        <% else %>
          <!-- Results count -->
          <div class="mb-4 text-sm text-gray-600">
            <%= @total_entries %> venues found
          </div>

          <!-- Venues grid -->
          <%= if @venues == [] do %>
            <div class="text-center py-12">
              <Heroicons.building_office_2 class="mx-auto h-12 w-12 text-gray-400" />
              <h3 class="mt-2 text-sm font-medium text-gray-900">No venues found</h3>
              <p class="mt-1 text-sm text-gray-500">
                <%= if @search do %>
                  Try adjusting your search terms
                <% else %>
                  Check back later for new venues
                <% end %>
              </p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for venue <- @venues do %>
                <.link
                  navigate={~p"/venues/#{venue.slug}"}
                  class="block bg-white rounded-xl border border-gray-200 p-6 hover:shadow-lg transition-shadow"
                >
                  <h3 class="text-lg font-semibold text-gray-900 group-hover:text-indigo-600">
                    <%= venue.name %>
                  </h3>
                  <%= if venue.city_ref do %>
                    <p class="mt-1 text-sm text-gray-500">
                      <%= venue.city_ref.name %>
                    </p>
                  <% end %>
                  <%= if venue.address do %>
                    <p class="mt-1 text-sm text-gray-400 line-clamp-1">
                      <%= venue.address %>
                    </p>
                  <% end %>
                  <div class="mt-4 flex items-center gap-2 text-sm text-indigo-600">
                    <Heroicons.calendar class="h-4 w-4" />
                    <span><%= venue.upcoming_event_count %> upcoming events</span>
                  </div>
                </.link>
              <% end %>
            </div>

            <!-- Load More (Keyset Pagination) -->
            <%= if @has_more do %>
              <div class="mt-8 flex justify-center">
                <button
                  phx-click="load_more"
                  class="px-6 py-3 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors font-medium"
                >
                  Load More Venues
                </button>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
