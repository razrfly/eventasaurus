defmodule EventasaurusWeb.Components.EventListing.EventResults do
  @moduledoc """
  Event results display components.

  Renders events in grid or list view, handling different event types
  (regular events, aggregated movies, aggregated containers).

  ## Example

      <.event_results
        events={@events}
        view_mode={@view_mode}
        language={@language}
        pagination={@pagination}
      />
  """

  use Phoenix.Component

  # Only import specific functions to avoid conflict with local is_aggregated?/1
  import EventasaurusWeb.Components.EventCards,
    only: [
      event_card: 1,
      aggregated_movie_card: 1,
      aggregated_container_card: 1,
      aggregated_event_card: 1
    ]

  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup

  @doc """
  Renders event results in the specified view mode.

  ## Attributes

  - `events` - List of events (can include AggregatedMovieGroup, AggregatedContainerGroup, or regular events)
  - `view_mode` - Display mode: "grid" or "list" (default: "grid")
  - `language` - Language code for localized content (default: "en")
  - `pagination` - Pagination struct with page_number, page_size, total_entries (optional)
  - `total_events` - DEPRECATED: Use pagination instead. Total count for display (optional)
  - `show_city` - Whether to show city in event cards (default: false)
  """
  attr :events, :list, required: true
  attr :view_mode, :string, default: "grid"
  attr :language, :string, default: "en"
  attr :pagination, :any, default: nil
  attr :total_events, :integer, default: nil
  attr :show_city, :boolean, default: false

  def event_results(assigns) do
    # Calculate range display info
    assigns = assign_range_info(assigns)

    ~H"""
    <div>
      <%= if @range_text do %>
        <div class="mb-4 text-sm text-gray-600">
          {@range_text}
        </div>
      <% end %>

      <%= if @view_mode == "grid" do %>
        <.event_grid events={@events} language={@language} show_city={@show_city} />
      <% else %>
        <.event_list events={@events} language={@language} show_city={@show_city} />
      <% end %>
    </div>
    """
  end

  @doc """
  Renders events in a responsive grid layout.
  """
  attr :events, :list, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: false

  def event_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      <%= for item <- @events do %>
        <.render_event_item item={item} language={@language} show_city={@show_city} />
      <% end %>
    </div>
    """
  end

  @doc """
  Renders events in a vertical list layout.
  """
  attr :events, :list, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: false

  def event_list(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= for item <- @events do %>
        <.render_event_item item={item} language={@language} show_city={@show_city} />
      <% end %>
    </div>
    """
  end

  # Private component to render individual event items based on type
  attr :item, :any, required: true
  attr :language, :string, default: "en"
  attr :show_city, :boolean, default: false

  defp render_event_item(assigns) do
    ~H"""
    <%= cond do %>
      <% match?(%AggregatedMovieGroup{}, @item) -> %>
        <.aggregated_movie_card group={@item} language={@language} show_city={@show_city} />
      <% match?(%AggregatedContainerGroup{}, @item) -> %>
        <.aggregated_container_card group={@item} language={@language} show_city={@show_city} />
      <% match?(%AggregatedEventGroup{}, @item) -> %>
        <.aggregated_event_card group={@item} language={@language} show_city={@show_city} />
      <% true -> %>
        <.event_card event={@item} language={@language} show_city={@show_city} />
    <% end %>
    """
  end

  # Calculate the range text for display (e.g., "Showing 1-30 of 111 events")
  defp assign_range_info(assigns) do
    cond do
      # New pagination struct provided - show range
      assigns[:pagination] != nil and is_map(assigns.pagination) ->
        pagination = assigns.pagination
        page_number = pagination.page_number || pagination[:page_number] || 1
        page_size = pagination.page_size || pagination[:page_size] || 30
        total = pagination.total_entries || pagination[:total_entries] || 0

        # Get actual count of events being displayed on this page
        current_page_count = length(assigns[:events] || [])

        if current_page_count > 0 do
          start_idx = (page_number - 1) * page_size + 1
          # Use actual displayed count for end index, not page math
          end_idx = start_idx + current_page_count - 1

          range_text =
            if total <= page_size do
              # Single page - just show actual count displayed
              "Showing #{current_page_count} events"
            else
              "Showing #{start_idx}-#{end_idx} of #{total} events"
            end

          assign(assigns, :range_text, range_text)
        else
          assign(assigns, :range_text, nil)
        end

      # Legacy: total_events provided without pagination
      assigns[:total_events] != nil ->
        assign(assigns, :range_text, "Found #{assigns.total_events} events")

      # No pagination info
      true ->
        assign(assigns, :range_text, nil)
    end
  end
end
