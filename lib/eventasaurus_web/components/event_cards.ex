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
  use Gettext, backend: EventasaurusWeb.Gettext

  alias EventasaurusDiscovery.PublicEvents.{
    PublicEvent,
    AggregatedEventGroup,
    AggregatedContainerGroup
  }

  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusWeb.Helpers.CategoryHelpers
  import EventasaurusWeb.Components.CDNImage
  import EventasaurusWeb.Helpers.PublicEventDisplayHelpers

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
  - `:event` - The PublicEvent struct or map to display (supports fallback data)
  - `:language` - Current language (optional)
  - `:show_city` - Whether to display city name (default: true)

  Note: This component accepts both PublicEvent structs and plain maps
  to support the materialized view fallback (Issue #3373).
  """
  attr :event, :map, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def event_card(%{event: %{slug: nil}} = assigns) do
    ~H"""
    """
  end

  def event_card(assigns) do
    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block">
      <div class={"bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow #{if event_recurring?(@event), do: "ring-2 ring-green-500 ring-offset-2", else: ""}"}>
        <!-- Event Image -->
        <div class="h-48 bg-gray-200 rounded-t-lg relative overflow-hidden">
          <%= if Map.get(@event, :cover_image_url) do %>
            <.cdn_img src={@event.cover_image_url} alt={@event.title} width={400} height={300} fit="cover" quality={85} class="w-full h-full object-cover" />
          <% else %>
            <div class="w-full h-full flex items-center justify-center">
              <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
              </svg>
            </div>
          <% end %>

          <%= if event_categories(@event) != [] do %>
            <% category = CategoryHelpers.get_preferred_category(event_categories(@event)) %>
            <%= if category && Map.get(category, :color) do %>
              <div
                class="absolute top-3 left-3 px-2 py-1 rounded-md text-xs font-medium text-white"
                style={"background-color: #{category.color}"}
              >
                <%= category.name %>
              </div>
            <% end %>
          <% end %>

          <!-- Time-Sensitive Badge -->
          <%= if badge = get_time_sensitive_badge(@event) do %>
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
          <%= if event_recurring?(@event) do %>
            <div class="absolute bottom-3 right-3 bg-green-500 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center">
              <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
              </svg>
              <%= event_occurrence_count(@event) %> dates
            </div>
          <% end %>
        </div>

        <!-- Event Details -->
        <div class="p-4">
          <h3 class="font-semibold text-lg text-gray-900 line-clamp-2">
            <%= Map.get(@event, :display_title) || @event.title %>
          </h3>

          <div class="mt-2 flex items-center text-sm text-gray-600">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= cond do %>
              <% event_recurring?(@event) -> %>
                <%= if next = event_next_occurrence_date(@event) do %>
                  <span class="text-green-600 font-medium">
                    <%= event_frequency_label(@event) %> • Next: <%= format_local_datetime(next, @event.venue, :short) %>
                  </span>
                <% else %>
                  <span class="text-green-600 font-medium"><%= event_frequency_label(@event) %></span>
                <% end %>
              <% is_exhibition?(@event) -> %>
                <%= if exhibition_datetime = format_exhibition_datetime(@event) do %>
                  <span><%= exhibition_datetime %></span>
                <% else %>
                  <span><%= gettext("Currently showing") %></span>
                <% end %>
              <% true -> %>
                <%= format_local_datetime(@event.starts_at, @event.venue, :short) %>
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
            <.cdn_img src={@group.movie_backdrop_url} alt={@group.movie_title} width={400} height={300} fit="cover" quality={85} class="w-full h-full object-cover" />
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

          <%= if @show_city && Ecto.assoc_loaded?(@group.city) && @group.city do %>
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
            <.cdn_img src={@group.cover_image_url} alt={@group.source_name} width={400} height={300} fit="cover" quality={85} class="w-full h-full object-cover" />
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

          <%= if @show_city && Ecto.assoc_loaded?(@group.city) && @group.city do %>
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
            <.cdn_img src={@group.cover_image_url} alt={@group.container_title} width={400} height={300} fit="cover" quality={85} class="w-full h-full object-cover" />
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

          <%= if @show_city && Ecto.assoc_loaded?(@group.city) && @group.city do %>
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

  # =============================================================================
  # Helper functions for event_card that work with both PublicEvent structs
  # and plain maps (from aggregation pipeline)
  # =============================================================================

  # Check if event is recurring (works with both structs and maps)
  defp event_recurring?(%PublicEvent{} = event), do: PublicEvent.recurring?(event)

  defp event_recurring?(event) when is_map(event) do
    event_occurrence_count(event) > 1
  end

  # Get occurrence count (works with both structs and maps)
  defp event_occurrence_count(%PublicEvent{} = event), do: PublicEvent.occurrence_count(event)

  defp event_occurrence_count(event) when is_map(event) do
    case Map.get(event, :occurrences) do
      %{"dates" => dates} when is_list(dates) -> length(dates)
      _ -> 1
    end
  end

  # Get next occurrence date (works with both structs and maps)
  defp event_next_occurrence_date(%PublicEvent{} = event),
    do: PublicEvent.next_occurrence_date(event)

  defp event_next_occurrence_date(event) when is_map(event) do
    # For fallback maps, just use starts_at as the next date
    Map.get(event, :starts_at)
  end

  # Get frequency label (works with both structs and maps)
  defp event_frequency_label(%PublicEvent{} = event), do: PublicEvent.frequency_label(event)

  defp event_frequency_label(event) when is_map(event) do
    count = event_occurrence_count(event)

    cond do
      count == 0 -> nil
      count == 1 -> nil
      count <= 7 -> "#{count} dates available"
      count <= 30 -> "Multiple dates"
      true -> "Many dates"
    end
  end

  # Get categories (works with both structs and maps)
  # Handles: struct with categories association, map with categories list,
  # map with single category (from fallback)
  defp event_categories(%PublicEvent{categories: categories}) when is_list(categories),
    do: categories

  defp event_categories(%{categories: categories}) when is_list(categories), do: categories
  defp event_categories(%{category: category}) when not is_nil(category), do: [category]
  defp event_categories(_), do: []

  # Get time-sensitive badge (works with both structs and maps)
  # For maps without full struct, we compute a simpler badge based on starts_at
  defp get_time_sensitive_badge(%PublicEvent{} = event) do
    PublicEventsEnhanced.get_time_sensitive_badge(event)
  end

  defp get_time_sensitive_badge(event) when is_map(event) do
    # Simplified badge logic for fallback maps
    case Map.get(event, :starts_at) do
      nil ->
        nil

      starts_at ->
        now = DateTime.utc_now()
        diff_days = DateTime.diff(starts_at, now, :day)

        cond do
          # Past event
          diff_days < 0 -> nil
          diff_days == 0 -> %{type: :last_chance, label: "Today"}
          diff_days == 1 -> %{type: :this_week, label: "Tomorrow"}
          diff_days <= 7 -> %{type: :this_week, label: "This week"}
          diff_days <= 14 -> %{type: :upcoming, label: "Coming soon"}
          true -> nil
        end
    end
  end

  # =============================================================================
  # Compact Row Components (List View)
  # =============================================================================

  @doc """
  Renders a compact row for a regular PublicEvent in list view.

  Layout: 60px thumbnail | details (category, title, date/venue) | trailing badge
  """
  @spec event_compact_row(map()) :: Phoenix.LiveView.Rendered.t()
  attr :event, :map, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def event_compact_row(%{event: %{slug: nil}} = assigns) do
    ~H"""
    """
  end

  def event_compact_row(assigns) do
    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="flex items-center gap-3 py-3 px-2 hover:bg-gray-50 transition-colors">
      <!-- Thumbnail -->
      <div class="w-[60px] h-[60px] rounded-lg overflow-hidden flex-shrink-0 bg-gray-200">
        <%= if Map.get(@event, :cover_image_url) do %>
          <.cdn_img src={@event.cover_image_url} alt={@event.title} width={120} height={120} fit="cover" quality={80} class="w-full h-full object-cover" />
        <% else %>
          <div class="w-full h-full flex items-center justify-center">
            <svg class="w-6 h-6 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
            </svg>
          </div>
        <% end %>
      </div>

      <!-- Details -->
      <div class="flex-1 min-w-0">
        <%= if event_categories(@event) != [] do %>
          <% category = CategoryHelpers.get_preferred_category(event_categories(@event)) %>
          <%= if category && Map.get(category, :color) do %>
            <span
              class="inline-block px-1.5 py-0.5 rounded text-[10px] font-medium text-white mb-0.5"
              style={"background-color: #{category.color}"}
            >
              <%= category.name %>
            </span>
          <% end %>
        <% end %>

        <h3 class="font-semibold text-sm text-gray-900 line-clamp-1">
          <%= Map.get(@event, :display_title) || @event.title %>
        </h3>

        <div class="flex items-center gap-2 text-xs text-gray-500 mt-0.5">
          <span class="flex items-center">
            <Heroicons.calendar class="w-3 h-3 mr-0.5 flex-shrink-0" />
            <%= cond do %>
              <% event_recurring?(@event) -> %>
                <%= if next = event_next_occurrence_date(@event) do %>
                  <span class="text-green-600"><%= format_local_datetime(next, @event.venue, :short) %></span>
                <% else %>
                  <span class="text-green-600"><%= event_frequency_label(@event) %></span>
                <% end %>
              <% is_exhibition?(@event) -> %>
                <%= if exhibition_datetime = format_exhibition_datetime(@event) do %>
                  <span><%= exhibition_datetime %></span>
                <% else %>
                  <span><%= gettext("Currently showing") %></span>
                <% end %>
              <% true -> %>
                <%= format_local_datetime(@event.starts_at, @event.venue, :short) %>
            <% end %>
          </span>
          <%= if @event.venue do %>
            <span class="flex items-center truncate">
              <Heroicons.map_pin class="w-3 h-3 mr-0.5 flex-shrink-0" />
              <span class="truncate"><%= @event.venue.name %></span>
            </span>
          <% end %>
          <% city = if @event.venue, do: Map.get(@event.venue, :city) %>
          <%= if @show_city && city && not match?(%Ecto.Association.NotLoaded{}, city) do %>
            <span class="flex items-center truncate">
              <Heroicons.map_pin class="w-3 h-3 mr-0.5 flex-shrink-0" />
              <span class="truncate"><%= city.name %></span>
            </span>
          <% end %>
        </div>
      </div>

      <!-- Trailing Badge -->
      <div class="flex-shrink-0 ml-auto">
        <%= cond do %>
          <% event_recurring?(@event) -> %>
            <span class="inline-flex items-center px-2 py-1 rounded-md text-[10px] font-medium bg-green-100 text-green-700">
              <%= event_occurrence_count(@event) %> dates
            </span>
          <% badge = get_time_sensitive_badge(@event) -> %>
            <span class={[
              "inline-flex items-center px-2 py-1 rounded-md text-[10px] font-medium text-white",
              case badge.type do
                :last_chance -> "bg-red-500"
                :this_week -> "bg-orange-500"
                :upcoming -> "bg-blue-500"
                _ -> "bg-gray-500"
              end
            ]}>
              <%= badge.label %>
            </span>
          <% true -> %>
        <% end %>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a compact row for an AggregatedMovieGroup in list view.
  """
  @spec aggregated_movie_compact_row(map()) :: Phoenix.LiveView.Rendered.t()
  attr :group, AggregatedMovieGroup, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def aggregated_movie_compact_row(assigns) do
    ~H"""
    <.link navigate={AggregatedMovieGroup.path(@group)} class="flex items-center gap-3 py-3 px-2 hover:bg-blue-50 transition-colors">
      <!-- Thumbnail -->
      <div class="w-[60px] h-[60px] rounded-lg overflow-hidden flex-shrink-0 bg-gray-200 ring-2 ring-blue-500">
        <%= if @group.movie_backdrop_url do %>
          <.cdn_img src={@group.movie_backdrop_url} alt={@group.movie_title} width={120} height={120} fit="cover" quality={80} class="w-full h-full object-cover" />
        <% else %>
          <div class="w-full h-full flex items-center justify-center">
            <Heroicons.film class="w-6 h-6 text-gray-400" />
          </div>
        <% end %>
      </div>

      <!-- Details -->
      <div class="flex-1 min-w-0">
        <%= if @group.categories && @group.categories != [] do %>
          <% category = CategoryHelpers.get_preferred_category(@group.categories) %>
          <%= if category do %>
            <span class="inline-block px-1.5 py-0.5 rounded text-[10px] font-medium text-white bg-blue-600 mb-0.5">
              <%= category.name %>
            </span>
          <% end %>
        <% end %>

        <h3 class="font-semibold text-sm text-gray-900 line-clamp-1">
          <%= AggregatedMovieGroup.title(@group) %>
        </h3>

        <div class="flex items-center gap-2 text-xs text-gray-500 mt-0.5">
          <span class="flex items-center text-blue-600">
            <Heroicons.calendar class="w-3 h-3 mr-0.5 flex-shrink-0" />
            Movie Screenings
          </span>
          <span class="flex items-center truncate">
            <Heroicons.building_storefront class="w-3 h-3 mr-0.5 flex-shrink-0" />
            <span class="truncate"><%= AggregatedMovieGroup.description(@group) %></span>
          </span>
          <%= if @show_city && Ecto.assoc_loaded?(@group.city) && @group.city do %>
            <span class="flex items-center truncate">
              <Heroicons.map_pin class="w-3 h-3 mr-0.5 flex-shrink-0" />
              <span class="truncate"><%= @group.city.name %></span>
            </span>
          <% end %>
        </div>
      </div>

      <!-- Trailing Badge -->
      <div class="flex-shrink-0 ml-auto">
        <span class="inline-flex items-center px-2 py-1 rounded-md text-[10px] font-medium bg-blue-100 text-blue-700">
          <Heroicons.film class="w-3 h-3 mr-0.5" />
          <%= @group.screening_count %> screenings
        </span>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a compact row for an AggregatedEventGroup in list view (recurring events).
  """
  @spec aggregated_event_compact_row(map()) :: Phoenix.LiveView.Rendered.t()
  attr :group, AggregatedEventGroup, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def aggregated_event_compact_row(assigns) do
    ~H"""
    <.link navigate={AggregatedEventGroup.path(@group)} class="flex items-center gap-3 py-3 px-2 hover:bg-green-50 transition-colors">
      <!-- Thumbnail -->
      <div class="w-[60px] h-[60px] rounded-lg overflow-hidden flex-shrink-0 bg-gray-200 ring-2 ring-green-500">
        <%= if @group.cover_image_url do %>
          <.cdn_img src={@group.cover_image_url} alt={@group.source_name} width={120} height={120} fit="cover" quality={80} class="w-full h-full object-cover" />
        <% else %>
          <div class="w-full h-full flex items-center justify-center">
            <svg class="w-6 h-6 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
            </svg>
          </div>
        <% end %>
      </div>

      <!-- Details -->
      <div class="flex-1 min-w-0">
        <%= if @group.categories && @group.categories != [] do %>
          <% category = CategoryHelpers.get_preferred_category(@group.categories) %>
          <%= if category && category.color do %>
            <span
              class="inline-block px-1.5 py-0.5 rounded text-[10px] font-medium text-white mb-0.5"
              style={"background-color: #{category.color}"}
            >
              <%= category.name %>
            </span>
          <% end %>
        <% end %>

        <h3 class="font-semibold text-sm text-gray-900 line-clamp-1">
          <%= AggregatedEventGroup.title(@group) %>
        </h3>

        <div class="flex items-center gap-2 text-xs text-gray-500 mt-0.5">
          <span class="flex items-center text-green-600">
            <Heroicons.calendar class="w-3 h-3 mr-0.5 flex-shrink-0" />
            <%= @group.aggregation_type |> to_string() |> String.capitalize() %>
          </span>
          <span class="flex items-center truncate">
            <Heroicons.building_storefront class="w-3 h-3 mr-0.5 flex-shrink-0" />
            <span class="truncate"><%= AggregatedEventGroup.description(@group) %></span>
          </span>
          <%= if @show_city && Ecto.assoc_loaded?(@group.city) && @group.city do %>
            <span class="flex items-center truncate">
              <Heroicons.map_pin class="w-3 h-3 mr-0.5 flex-shrink-0" />
              <span class="truncate"><%= @group.city.name %></span>
            </span>
          <% end %>
        </div>
      </div>

      <!-- Trailing Badge -->
      <div class="flex-shrink-0 ml-auto">
        <span class="inline-flex items-center px-2 py-1 rounded-md text-[10px] font-medium bg-green-100 text-green-700">
          <%= @group.event_count %> events
        </span>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a compact row for an AggregatedContainerGroup in list view (festivals, conferences, etc.).
  """
  @spec aggregated_container_compact_row(map()) :: Phoenix.LiveView.Rendered.t()
  attr :group, AggregatedContainerGroup, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: true

  def aggregated_container_compact_row(assigns) do
    ring_color = AggregatedContainerGroup.ring_color_class(assigns.group)
    badge_color = get_container_badge_color(assigns.group.container_type)
    text_color = get_container_text_color(assigns.group.container_type)
    hover_color = get_container_hover_color(assigns.group.container_type)

    assigns =
      assigns
      |> assign(:ring_color, ring_color)
      |> assign(:badge_color, badge_color)
      |> assign(:text_color, text_color)
      |> assign(:hover_color, hover_color)

    ~H"""
    <.link navigate={AggregatedContainerGroup.path(@group)} class={"flex items-center gap-3 py-3 px-2 #{@hover_color} transition-colors"}>
      <!-- Thumbnail -->
      <div class={"w-[60px] h-[60px] rounded-lg overflow-hidden flex-shrink-0 bg-gray-200 ring-2 #{@ring_color}"}>
        <%= if @group.cover_image_url do %>
          <.cdn_img src={@group.cover_image_url} alt={@group.container_title} width={120} height={120} fit="cover" quality={80} class="w-full h-full object-cover" />
        <% else %>
          <div class="w-full h-full flex items-center justify-center">
            <svg class="w-6 h-6 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
            </svg>
          </div>
        <% end %>
      </div>

      <!-- Details -->
      <div class="flex-1 min-w-0">
        <span class={"inline-block px-1.5 py-0.5 rounded text-[10px] font-medium text-white #{@badge_color} mb-0.5"}>
          <%= AggregatedContainerGroup.type_label(@group) %>
        </span>

        <h3 class="font-semibold text-sm text-gray-900 line-clamp-1">
          <%= AggregatedContainerGroup.title(@group) %>
        </h3>

        <div class="flex items-center gap-2 text-xs text-gray-500 mt-0.5">
          <span class={"flex items-center #{@text_color}"}>
            <Heroicons.calendar class="w-3 h-3 mr-0.5 flex-shrink-0" />
            <%= AggregatedContainerGroup.date_range_text(@group) %>
          </span>
          <span class="flex items-center truncate">
            <Heroicons.building_storefront class="w-3 h-3 mr-0.5 flex-shrink-0" />
            <span class="truncate"><%= AggregatedContainerGroup.description(@group) %></span>
          </span>
          <%= if @show_city && Ecto.assoc_loaded?(@group.city) && @group.city do %>
            <span class="flex items-center truncate">
              <Heroicons.map_pin class="w-3 h-3 mr-0.5 flex-shrink-0" />
              <span class="truncate"><%= @group.city.name %></span>
            </span>
          <% end %>
        </div>
      </div>

      <!-- Trailing Badge -->
      <div class="flex-shrink-0 ml-auto">
        <span class={"inline-flex items-center px-2 py-1 rounded-md text-[10px] font-medium #{get_container_badge_light_color(@group.container_type)}"}>
          <%= @group.event_count %> events
        </span>
      </div>
    </.link>
    """
  end

  # =============================================================================
  # Helper functions for event_card that work with both PublicEvent structs
  # and plain maps (from aggregation pipeline)
  # =============================================================================

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

  defp get_container_hover_color(:festival), do: "hover:bg-purple-50"
  defp get_container_hover_color(:conference), do: "hover:bg-orange-50"
  defp get_container_hover_color(:tour), do: "hover:bg-red-50"
  defp get_container_hover_color(:series), do: "hover:bg-indigo-50"
  defp get_container_hover_color(:exhibition), do: "hover:bg-yellow-50"
  defp get_container_hover_color(:tournament), do: "hover:bg-pink-50"
  defp get_container_hover_color(_), do: "hover:bg-gray-50"

  defp get_container_badge_light_color(:festival), do: "bg-purple-100 text-purple-700"
  defp get_container_badge_light_color(:conference), do: "bg-orange-100 text-orange-700"
  defp get_container_badge_light_color(:tour), do: "bg-red-100 text-red-700"
  defp get_container_badge_light_color(:series), do: "bg-indigo-100 text-indigo-700"
  defp get_container_badge_light_color(:exhibition), do: "bg-yellow-100 text-yellow-700"
  defp get_container_badge_light_color(:tournament), do: "bg-pink-100 text-pink-700"
  defp get_container_badge_light_color(_), do: "bg-gray-100 text-gray-700"
end
