defmodule EventasaurusWeb.VenuesIndexLive do
  @moduledoc """
  Venues index page showing all public venues.

  Issue #3143: Part of the simplified venue routing structure.
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
      |> assign(:pagination, %Pagination{
        entries: [],
        page_number: 1,
        page_size: @default_page_size,
        total_entries: 0,
        total_pages: 0
      })

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _url, socket) do
    page = parse_page(params["page"])
    search = params["search"]

    {venues, pagination} = load_venues(page, search)

    socket =
      socket
      |> assign(:venues, venues)
      |> assign(:search, search)
      |> assign(:pagination, pagination)
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
    {:noreply, push_patch(socket, to: build_path(search, 1))}
  end

  @impl true
  def handle_event("clear_search", _params, socket) do
    {:noreply, push_patch(socket, to: "/venues")}
  end

  @impl true
  def handle_event("paginate", %{"page" => page_string}, socket) do
    page = String.to_integer(page_string)
    {:noreply, push_patch(socket, to: build_path(socket.assigns.search, page))}
  end

  defp load_venues(page, search) do
    base_query =
      from(v in Venue,
        left_join: c in assoc(v, :city_ref),
        where: v.is_public == true,
        where: not is_nil(v.slug),
        preload: [city_ref: c],
        order_by: [asc: v.name]
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

    # Count total
    total = Repo.aggregate(query, :count)

    # Get page of venues
    venues =
      from(v in query,
        offset: ^((page - 1) * @default_page_size),
        limit: ^@default_page_size
      )
      |> Repo.all()

    # Batch load event counts to avoid N+1 queries
    venue_ids = Enum.map(venues, & &1.id)
    event_counts = batch_count_venue_events(venue_ids)

    # Merge event counts into venues
    venues =
      Enum.map(venues, fn venue ->
        count = Map.get(event_counts, venue.id, 0)
        Map.put(venue, :upcoming_event_count, count)
      end)

    total_pages = ceil(total / @default_page_size)

    pagination = %Pagination{
      entries: venues,
      page_number: page,
      page_size: @default_page_size,
      total_entries: total,
      total_pages: total_pages
    }

    {venues, pagination}
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

  defp parse_page(nil), do: 1
  defp parse_page(""), do: 1

  defp parse_page(page_string) when is_binary(page_string) do
    case Integer.parse(page_string) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp build_path(search, page) do
    params =
      %{}
      |> maybe_add_param("search", search)
      |> maybe_add_param("page", if(page > 1, do: to_string(page)))

    if map_size(params) > 0 do
      "/venues?#{URI.encode_query(params)}"
    else
      "/venues"
    end
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, _key, ""), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

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
            <%= @pagination.total_entries %> venues found
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

            <!-- Pagination -->
            <%= if @pagination.total_pages > 1 do %>
              <div class="mt-8 flex justify-center">
                <nav class="flex items-center gap-2">
                  <%= if @pagination.page_number > 1 do %>
                    <button
                      phx-click="paginate"
                      phx-value-page={@pagination.page_number - 1}
                      class="px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-lg"
                    >
                      Previous
                    </button>
                  <% end %>

                  <span class="px-4 py-2 text-sm text-gray-600">
                    Page <%= @pagination.page_number %> of <%= @pagination.total_pages %>
                  </span>

                  <%= if @pagination.page_number < @pagination.total_pages do %>
                    <button
                      phx-click="paginate"
                      phx-value-page={@pagination.page_number + 1}
                      class="px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-lg"
                    >
                      Next
                    </button>
                  <% end %>
                </nav>
              </div>
            <% end %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
