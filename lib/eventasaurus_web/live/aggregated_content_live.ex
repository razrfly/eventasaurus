defmodule EventasaurusWeb.AggregatedContentLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Locations
  alias EventasaurusWeb.Helpers.CategoryHelpers

  @impl true
  def mount(
        %{"city_slug" => city_slug, "content_type" => content_type, "identifier" => identifier},
        _session,
        socket
      ) do
    # Look up city
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/activities")}

      city ->
        # Fetch all events for this content type + identifier in this city
        events = fetch_aggregated_events(content_type, identifier, city)

        # Group events by venue (one representative event per venue)
        venue_groups =
          events
          |> Enum.group_by(& &1.venue_id)
          |> Enum.map(fn {_venue_id, venue_events} ->
            # Take the first event as the representative for this venue
            %{event: List.first(venue_events)}
          end)
          |> Enum.sort_by(& &1.event.venue.name)

        {:ok,
         socket
         |> assign(:city, city)
         |> assign(:content_type, content_type)
         |> assign(:identifier, identifier)
         |> assign(:venue_schedules, venue_groups)
         |> assign(:page_title, format_page_title(content_type, identifier, city))
         |> assign(:source_name, get_source_name(identifier))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header Section -->
      <div class="mb-8">
        <nav class="text-sm text-gray-500 mb-4">
          <.link navigate={~p"/c/#{@city.slug}"} class="hover:text-gray-700">
            <%= @city.name %>
          </.link>
          <span class="mx-2">→</span>
          <span class="capitalize text-gray-700"><%= @content_type %></span>
          <span class="mx-2">→</span>
          <span class="text-gray-900"><%= @source_name %></span>
        </nav>

        <h1 class="text-4xl font-bold text-gray-900">
          <%= @source_name %> in <%= @city.name %>
        </h1>

        <div class="mt-4 flex items-center text-gray-600">
          <Heroicons.building_storefront class="w-5 h-5 mr-2" />
          <span><%= length(@venue_schedules) %> <%= ngettext("location", "locations", length(@venue_schedules)) %> across the city</span>
        </div>
      </div>

      <!-- Venue Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for schedule <- @venue_schedules do %>
          <.event_card event={schedule.event} />
        <% end %>
      </div>
    </div>
    """
  end

  defp event_card(assigns) do
    alias EventasaurusDiscovery.PublicEvents.PublicEvent

    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block">
      <div class={"bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow #{if PublicEvent.recurring?(@event), do: "ring-2 ring-green-500 ring-offset-2", else: ""}"}>
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
            <% category = CategoryHelpers.get_preferred_category(@event.categories) %>
            <%= if category && category.color do %>
              <div
                class="absolute top-3 left-3 px-2 py-1 rounded-md text-xs font-medium text-white"
                style={"background-color: #{category.color}"}
              >
                <%= category.name %>
              </div>
            <% end %>
          <% end %>
          <!-- Time-Sensitive Badge -->
          <%= if badge = PublicEventsEnhanced.get_time_sensitive_badge(@event) do %>
            <div class={[
              "absolute top-3 right-3 text-white px-2 py-1 rounded-md text-xs font-medium",
              case badge.type do
                :last_chance -> "bg-red-500"
                :this_week -> "bg-orange-500"
                :upcoming -> "bg-blue-500"
                _ -> "bg-gray-500"
              end
            ]}>
              <%= badge.label %>
            </div>
          <% end %>
          <!-- Recurring Event Badge -->
          <%= if PublicEvent.recurring?(@event) do %>
            <div class="absolute bottom-3 right-3 bg-green-500 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center">
              <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
              </svg>
              <%= PublicEvent.occurrence_count(@event) %> dates
            </div>
          <% end %>
        </div>
        <!-- Event Details -->
        <div class="p-4">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-2">
            <%= @event.display_title || @event.title %>
          </h3>
          <div class="mt-2 flex items-center text-sm text-gray-600">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= if PublicEvent.recurring?(@event) do %>
              <span class="text-green-600 font-medium">
                <%= PublicEvent.frequency_label(@event) %> • Next: <%= format_datetime(PublicEvent.next_occurrence_date(@event)) %>
              </span>
            <% else %>
              <%= format_datetime(@event.starts_at) %>
            <% end %>
          </div>
          <%= if @event.venue do %>
            <div class="mt-1 flex items-center text-sm text-gray-600">
              <Heroicons.map_pin class="w-4 h-4 mr-1" />
              <%= @event.venue.name %>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # Fetch events for a specific content type + identifier in a city
  defp fetch_aggregated_events(_content_type, identifier, city) do
    # For now, we'll use source slug as the identifier for trivia
    # In the future, this could handle movies by title, classes by name, etc.
    source_slug = identifier

    # Query events by source slug and city
    PublicEventsEnhanced.list_events(%{
      source_slug: source_slug,
      city_id: city.id,
      include_pattern_events: true
    })
  end

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d at %I:%M %p")
    |> String.replace(" 0", " ")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d at %I:%M %p")
    |> String.replace(" 0", " ")
  end

  defp format_datetime(_), do: "Date TBD"

  defp format_page_title(content_type, identifier, city) do
    source_name = get_source_name(identifier)
    "#{source_name} #{String.capitalize(content_type)} in #{city.name}"
  end

  defp get_source_name("pubquiz-pl"), do: "PubQuiz Poland"
  defp get_source_name(slug), do: slug |> String.replace("-", " ") |> String.capitalize()
end
