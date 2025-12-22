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
        total_events={@total_events}
      />
  """

  use Phoenix.Component

  # Only import specific functions to avoid conflict with local is_aggregated?/1
  import EventasaurusWeb.Components.EventCards,
    only: [event_card: 1, aggregated_movie_card: 1, aggregated_container_card: 1, aggregated_event_card: 1]

  alias EventasaurusDiscovery.Movies.AggregatedMovieGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedContainerGroup
  alias EventasaurusDiscovery.PublicEvents.AggregatedEventGroup

  @doc """
  Renders event results in the specified view mode.

  ## Attributes

  - `events` - List of events (can include AggregatedMovieGroup, AggregatedContainerGroup, or regular events)
  - `view_mode` - Display mode: "grid" or "list" (default: "grid")
  - `language` - Language code for localized content (default: "en")
  - `total_events` - Total count for display (optional)
  - `show_city` - Whether to show city in event cards (default: false)
  """
  attr :events, :list, required: true
  attr :view_mode, :string, default: "grid"
  attr :language, :string, default: "en"
  attr :total_events, :integer, default: nil
  attr :show_city, :boolean, default: false

  def event_results(assigns) do
    ~H"""
    <div>
      <%= if @total_events do %>
        <div class="mb-4 text-sm text-gray-600">
          Found {@total_events} events
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
      <% is_aggregated?(@item) -> %>
        <.aggregated_event_card group={@item} language={@language} show_city={@show_city} />
      <% true -> %>
        <.event_card event={@item} language={@language} show_city={@show_city} />
    <% end %>
    """
  end

  # Helper to check if an item is an aggregated group
  defp is_aggregated?(%{events: events}) when is_list(events) and length(events) > 1, do: true
  defp is_aggregated?(_), do: false
end
