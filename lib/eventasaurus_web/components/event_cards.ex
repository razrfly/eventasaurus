defmodule EventasaurusWeb.Components.EventCards do
  @moduledoc """
  Shared event card components used across city pages and activities pages.

  Provides consistent card rendering for:
  - Regular PublicEvents (concerts, markets, etc.)
  - AggregatedEventGroups (recurring events)
  - AggregatedMovieGroups (movie screenings)

  Components support both grid and list view modes.
  """

  use Phoenix.Component
  use EventasaurusWeb, :verified_routes

  alias EventasaurusDiscovery.PublicEvents.{
    PublicEvent,
    AggregatedEventGroup,
    AggregatedContainerGroup
  }

  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusWeb.Helpers.CategoryHelpers

  @doc """
  Check if an item is an aggregated group (recurring events, movies, or containers).
  """
  def is_aggregated?(%AggregatedEventGroup{}), do: true
  def is_aggregated?(%AggregatedMovieGroup{}), do: true
  def is_aggregated?(%AggregatedContainerGroup{}), do: true
  def is_aggregated?(_), do: false

  @doc """
  Renders an event card for grid view.

  ## Assigns
  - `:event` - The PublicEvent to display
  - `:language` - Current language (optional)
  - `:show_city` - Whether to display city name (default: true)
  """
  attr :event, PublicEvent, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def event_card(assigns) do
    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block">
      <div class={"bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow #{if PublicEvent.recurring?(@event), do: "ring-2 ring-green-500 ring-offset-2", else: ""}"}>
        <!-- Event Image -->
        <div class="h-48 bg-gray-200 rounded-t-lg relative overflow-hidden">
          <%= if @event.cover_image_url do %>
            <img src={@event.cover_image_url} alt={@event.title} class="w-full h-full object-cover" loading="lazy">
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

          <% city = if @event.venue, do: Map.get(@event.venue, :city) %>
          <%= if @show_city && city && not match?(%Ecto.Association.NotLoaded{}, city) do %>
            <div class="mt-1 flex items-center text-sm text-gray-600">
              <Heroicons.building_office class="w-4 h-4 mr-1" />
              <%= city.name %>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Renders an aggregated movie group card for grid view.
  """
  attr :group, AggregatedMovieGroup, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def aggregated_movie_card(assigns) do
    ~H"""
    <.link navigate={AggregatedMovieGroup.path(@group)} class="block">
      <div class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow ring-2 ring-blue-500 ring-offset-2">
        <!-- Movie Backdrop/Poster -->
        <div class="h-48 bg-gray-200 rounded-t-lg relative overflow-hidden">
          <%= if @group.movie_backdrop_url do %>
            <img src={@group.movie_backdrop_url} alt={@group.movie_title} class="w-full h-full object-cover" loading="lazy">
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <Heroicons.film class="w-12 h-12 text-gray-400" />
            </div>
          <% end %>

          <%= if @group.categories && @group.categories != [] do %>
            <% category = CategoryHelpers.get_preferred_category(@group.categories) %>
            <%= if category do %>
              <div class="absolute top-3 left-3 bg-blue-600 text-white px-2 py-1 rounded-md text-xs font-medium">
                <%= category.name %>
              </div>
            <% end %>
          <% end %>

          <!-- Movie Badge -->
          <div class="absolute top-3 right-3 bg-blue-500 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center">
            <Heroicons.film class="w-3 h-3 mr-1" />
            <%= @group.screening_count %> screenings
          </div>
        </div>

        <!-- Movie Details -->
        <div class="p-4">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-2">
            <%= AggregatedMovieGroup.title(@group) %>
          </h3>

          <div class="mt-2 flex items-center text-sm text-blue-600 font-medium">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            Movie Screenings
          </div>

          <div class="mt-1 flex items-center text-sm text-gray-600">
            <Heroicons.building_storefront class="w-4 h-4 mr-1" />
            <%= AggregatedMovieGroup.description(@group) %>
          </div>

          <%= if @show_city do %>
            <div class="mt-1 flex items-center text-sm text-gray-600">
              <Heroicons.map_pin class="w-4 h-4 mr-1" />
              <%= @group.city.name %>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Renders an aggregated event group card for grid view (recurring events).
  """
  attr :group, AggregatedEventGroup, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def aggregated_event_card(assigns) do
    ~H"""
    <.link navigate={AggregatedEventGroup.path(@group)} class="block">
      <div class="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow ring-2 ring-green-500 ring-offset-2">
        <!-- Event Image -->
        <div class="h-48 bg-gray-200 rounded-t-lg relative overflow-hidden">
          <%= if @group.cover_image_url do %>
            <img src={@group.cover_image_url} alt={@group.source_name} class="w-full h-full object-cover" loading="lazy">
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
              </svg>
            </div>
          <% end %>

          <%= if @group.categories && @group.categories != [] do %>
            <% category = CategoryHelpers.get_preferred_category(@group.categories) %>
            <%= if category && category.color do %>
              <div
                class="absolute top-3 left-3 px-2 py-1 rounded-md text-xs font-medium text-white"
                style={"background-color: #{category.color}"}
              >
                <%= category.name %>
              </div>
            <% end %>
          <% end %>

          <!-- Aggregated Badge -->
          <div class="absolute top-3 right-3 bg-green-500 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center">
            <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
            </svg>
            <%= @group.event_count %> events
          </div>
        </div>

        <!-- Event Details -->
        <div class="p-4">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-2">
            <%= AggregatedEventGroup.title(@group) %>
          </h3>

          <div class="mt-2 flex items-center text-sm text-green-600 font-medium">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= @group.aggregation_type |> to_string() |> String.capitalize() %>
          </div>

          <div class="mt-1 flex items-center text-sm text-gray-600">
            <Heroicons.building_storefront class="w-4 h-4 mr-1" />
            <%= AggregatedEventGroup.description(@group) %>
          </div>

          <%= if @show_city do %>
            <div class="mt-1 flex items-center text-sm text-gray-600">
              <Heroicons.map_pin class="w-4 h-4 mr-1" />
              <%= @group.city.name %>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Renders an aggregated container group card for grid view (festivals, conferences, tours, etc.).
  """
  attr :group, AggregatedContainerGroup, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def aggregated_container_card(assigns) do
    # Get ring color based on container type
    ring_color = AggregatedContainerGroup.ring_color_class(assigns.group)
    badge_color = get_container_badge_color(assigns.group.container_type)

    assigns = assign(assigns, :ring_color, ring_color)
    assigns = assign(assigns, :badge_color, badge_color)

    ~H"""
    <.link navigate={AggregatedContainerGroup.path(@group)} class="block">
      <div class={"bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow ring-2 #{@ring_color} ring-offset-2"}>
        <!-- Container Image -->
        <div class="h-48 bg-gray-200 rounded-t-lg relative overflow-hidden">
          <%= if @group.cover_image_url do %>
            <img src={@group.cover_image_url} alt={@group.container_title} class="w-full h-full object-cover" loading="lazy">
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
              </svg>
            </div>
          <% end %>

          <!-- Container Type Label -->
          <div class={"absolute top-3 left-3 px-2 py-1 rounded-md text-xs font-medium text-white #{@badge_color}"}>
            <%= AggregatedContainerGroup.type_label(@group) %>
          </div>

          <!-- Event Count Badge -->
          <div class={"absolute top-3 right-3 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center #{@badge_color}"}>
            <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
            </svg>
            <%= @group.event_count %> events
          </div>
        </div>

        <!-- Container Details -->
        <div class="p-4">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-2">
            <%= AggregatedContainerGroup.title(@group) %>
          </h3>

          <div class={"mt-2 flex items-center text-sm font-medium #{get_container_text_color(@group.container_type)}"}>
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= AggregatedContainerGroup.date_range_text(@group) %>
          </div>

          <div class="mt-1 flex items-center text-sm text-gray-600">
            <Heroicons.building_storefront class="w-4 h-4 mr-1" />
            <%= AggregatedContainerGroup.description(@group) %>
          </div>

          <%= if @show_city do %>
            <div class="mt-1 flex items-center text-sm text-gray-600">
              <Heroicons.map_pin class="w-4 h-4 mr-1" />
              <%= @group.city.name %>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # Helper functions for container styling
  defp get_container_badge_color(:festival), do: "bg-purple-500"
  defp get_container_badge_color(:conference), do: "bg-orange-500"
  defp get_container_badge_color(:tour), do: "bg-red-500"
  defp get_container_badge_color(:series), do: "bg-indigo-500"
  defp get_container_badge_color(:exhibition), do: "bg-yellow-500"
  defp get_container_badge_color(:tournament), do: "bg-pink-500"
  defp get_container_badge_color(_), do: "bg-gray-500"

  defp get_container_text_color(:festival), do: "text-purple-600"
  defp get_container_text_color(:conference), do: "text-orange-600"
  defp get_container_text_color(:tour), do: "text-red-600"
  defp get_container_text_color(:series), do: "text-indigo-600"
  defp get_container_text_color(:exhibition), do: "text-yellow-600"
  defp get_container_text_color(:tournament), do: "text-pink-600"
  defp get_container_text_color(_), do: "text-gray-600"

  # Helper function for datetime formatting
  defp format_datetime(nil), do: ""

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y • %I:%M %p")
  end

  defp format_datetime(date_str) when is_binary(date_str) do
    case DateTime.from_iso8601(date_str) do
      {:ok, datetime, _offset} -> format_datetime(datetime)
      _ -> date_str
    end
  end

  defp format_datetime(_), do: ""
end
