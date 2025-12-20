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
  alias EventasaurusDiscovery.PublicEventsEnhanced

  alias EventasaurusWeb.Components.{
    Breadcrumbs,
    EventListing
  }

  alias EventasaurusWeb.Components.Activity.{
    ActivityLayout,
    PerformerHeroCard
  }

  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
  alias EventasaurusWeb.Live.Helpers.EventFilters
  import EventasaurusWeb.EventComponents, only: [date_range_button: 1]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:performer, nil)
      |> assign(:loading, true)
      |> assign(:stats, %{})
      # EventListing handles upcoming events display; we track count for hero card
      |> assign(:upcoming_event_count, 0)
      |> assign(:past_event_count, 0)
      |> assign(:breadcrumb_items, [])
      |> assign(:language, "en")
      # Quick date filter state
      |> assign(:active_date_range, nil)
      |> assign(:date_range_counts, %{})
      |> assign(:all_events_count, 0)
      |> assign(:filters, %{})

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
        # Get stats and events (EventListing handles upcoming display)
        stats = PerformerStore.get_performer_stats(performer.id)
        events = PerformerStore.get_performer_events(performer.id)

        # Build breadcrumb items
        breadcrumb_items =
          BreadcrumbBuilder.build_performer_breadcrumbs(performer,
            gettext_backend: EventasaurusWeb.Gettext
          )

        # Calculate date range counts for quick filters
        performer_filter = %{performer_id: performer.id}
        date_range_counts = PublicEventsEnhanced.get_quick_date_range_counts(performer_filter)
        all_events_count = PublicEventsEnhanced.count_events(performer_filter)

        # Build initial filters with performer constraint
        filters = %{performer_id: performer.id}

        socket =
          socket
          |> assign(:performer, performer)
          |> assign(:stats, stats)
          # Track count for hero card and sidebar stats
          |> assign(:upcoming_event_count, length(events.upcoming))
          |> assign(:past_event_count, length(events.past))
          |> assign(:loading, false)
          |> assign(:page_title, performer.name)
          |> assign(:breadcrumb_items, breadcrumb_items)
          |> assign(:date_range_counts, date_range_counts)
          |> assign(:all_events_count, all_events_count)
          |> assign(:filters, filters)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("quick_date_filter", %{"range" => range}, socket) do
    case EventFilters.parse_quick_range(range) do
      {:ok, range_atom} ->
        # Apply the date filter using shared helper
        filters = EventFilters.apply_quick_date_filter(socket.assigns.filters, range_atom)

        # Set active_date_range (nil for :all, atom for others)
        active_date_range = if range_atom == :all, do: nil, else: range_atom

        socket =
          socket
          |> assign(:filters, filters)
          |> assign(:active_date_range, active_date_range)

        {:noreply, socket}

      :error ->
        # Invalid range - ignore the request
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_date_filter", _params, socket) do
    # Reset filters keeping only performer constraint
    performer_id = socket.assigns.performer.id
    filters = %{performer_id: performer_id}

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:active_date_range, nil)

    {:noreply, socket}
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
                upcoming_event_count={@upcoming_event_count}
                total_event_count={@stats.total_events}
              />

              <!-- Quick Date Filters -->
              <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mt-6">
                <div class="flex items-center justify-between mb-3">
                  <h2 class="text-sm font-medium text-gray-700">
                    <%= gettext("Quick date filters") %>
                  </h2>
                  <%= if @active_date_range do %>
                    <button
                      phx-click="clear_date_filter"
                      class="text-sm text-blue-600 hover:text-blue-800 flex items-center"
                    >
                      <Heroicons.x_mark class="w-4 h-4 mr-1" />
                      <%= gettext("Clear") %>
                    </button>
                  <% end %>
                </div>
                <div class="flex flex-wrap gap-2">
                  <.date_range_button
                    range={:all}
                    label={gettext("All Events")}
                    active={@active_date_range == nil}
                    count={@all_events_count}
                  />
                  <.date_range_button
                    range={:today}
                    label={gettext("Today")}
                    active={@active_date_range == :today}
                    count={Map.get(@date_range_counts, :today, 0)}
                  />
                  <.date_range_button
                    range={:tomorrow}
                    label={gettext("Tomorrow")}
                    active={@active_date_range == :tomorrow}
                    count={Map.get(@date_range_counts, :tomorrow, 0)}
                  />
                  <.date_range_button
                    range={:this_weekend}
                    label={gettext("This Weekend")}
                    active={@active_date_range == :this_weekend}
                    count={Map.get(@date_range_counts, :this_weekend, 0)}
                  />
                  <.date_range_button
                    range={:next_7_days}
                    label={gettext("Next 7 Days")}
                    active={@active_date_range == :next_7_days}
                    count={Map.get(@date_range_counts, :next_7_days, 0)}
                  />
                  <.date_range_button
                    range={:next_30_days}
                    label={gettext("Next 30 Days")}
                    active={@active_date_range == :next_30_days}
                    count={Map.get(@date_range_counts, :next_30_days, 0)}
                  />
                </div>
              </div>

              <!-- Events via EventListing Component (includes past events toggle) -->
              <.live_component
                module={EventListing}
                id="performer-events"
                constraint={{:performer_id, @performer.id}}
                language={@language}
                show_city={true}
                show_search={true}
                show_sort={true}
                show_past_toggle={true}
                sort_options={[:starts_at, :title]}
                empty_message={gettext("No upcoming events scheduled for this artist")}
                filters={@filters}
              />
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
                    <span class="font-semibold text-gray-900"><%= @upcoming_event_count %></span>
                  </div>
                  <div class="flex justify-between items-center">
                    <span class="text-gray-600"><%= gettext("Past Events") %></span>
                    <span class="font-semibold text-gray-900"><%= @past_event_count %></span>
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
