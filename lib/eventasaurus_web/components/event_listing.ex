defmodule EventasaurusWeb.Components.EventListing do
  @moduledoc """
  Reusable display components for event listings.

  These are pure function components (not LiveComponents) that render display-only UI.
  They receive data via props and emit events to the parent LiveView.

  ## Design Principles

  1. **Display Only**: Components render what they're given, no data fetching
  2. **Parent Owns State**: Parent LiveView manages filters, events, pagination
  3. **Events Bubble Up**: phx-click events naturally route to parent
  4. **Pure Functions**: Props in, HEEx out, no lifecycle complexity

  ## Components

  ### Filter Components
  - `filter_bar/1` - Quick date filters, search input, sort controls
  - `quick_date_filters/1` - Date range filter buttons with counts
  - `search_bar/1` - Search input form
  - `sort_controls/1` - Sort dropdown (date, distance, title)
  - `view_toggle/1` - Grid/list view toggle
  - `simple_filter_tags/1` - Active filter badges for entity pages

  ### Geographic & Category Filters
  - `radius_selector/1` - Radius dropdown for location-based filtering
  - `radius_selector_compact/1` - Compact inline radius selector
  - `category_checkboxes/1` - Category multi-select checkboxes
  - `category_tags/1` - Selected categories as removable tags
  - `category_dropdown/1` - Compact category dropdown
  - `category_pills/1` - Horizontal scrollable category pills

  ### Display Components
  - `event_results/1` - Tiered event display with cards
  - `event_grid/1` - Grid layout for events
  - `event_list/1` - List layout for events
  - `pagination/1` - Page navigation controls
  - `loading_skeleton/1` - Loading placeholder UI
  - `empty_state/1` - No results message

  ## Usage

  In your LiveView:

      import EventasaurusWeb.Components.EventListing

      def render(assigns) do
        ~H\"\"\"
        <.filter_bar
          filters={@filters}
          active_date_range={@active_date_range}
          date_range_counts={@date_range_counts}
          all_events_count={@all_events_count}
        />

        <%= if @loading do %>
          <.loading_skeleton />
        <% else %>
          <%= if @events == [] do %>
            <.empty_state message="No events found" />
          <% else %>
            <.event_results
              events={@events}
              view_mode={@view_mode}
              language={@language}
            />
            <.pagination pagination={@pagination} />
          <% end %>
        <% end %>
        \"\"\"
      end
  """

  use Phoenix.Component

  # Re-export all components via delegation (no imports needed)
  defdelegate filter_bar(assigns), to: EventasaurusWeb.Components.EventListing.FilterBar
  defdelegate quick_date_filters(assigns), to: EventasaurusWeb.Components.EventListing.FilterBar
  defdelegate search_bar(assigns), to: EventasaurusWeb.Components.EventListing.FilterBar
  defdelegate sort_controls(assigns), to: EventasaurusWeb.Components.EventListing.FilterBar
  defdelegate event_results(assigns), to: EventasaurusWeb.Components.EventListing.EventResults
  defdelegate event_grid(assigns), to: EventasaurusWeb.Components.EventListing.EventResults
  defdelegate event_list(assigns), to: EventasaurusWeb.Components.EventListing.EventResults
  defdelegate pagination(assigns), to: EventasaurusWeb.Components.EventListing.Pagination

  defdelegate loading_skeleton(assigns),
    to: EventasaurusWeb.Components.EventListing.LoadingSkeleton

  defdelegate empty_state(assigns), to: EventasaurusWeb.Components.EventListing.EmptyState
  defdelegate view_toggle(assigns), to: EventasaurusWeb.Components.EventListing.FilterBar
  defdelegate simple_filter_tags(assigns), to: EventasaurusWeb.Components.EventListing.FilterBar
  defdelegate date_filter_button(assigns), to: EventasaurusWeb.Components.EventListing.FilterBar
  defdelegate aggregation_toggle(assigns), to: EventasaurusWeb.Components.EventListing.FilterBar

  # Radius selector components
  defdelegate radius_selector(assigns),
    to: EventasaurusWeb.Components.EventListing.RadiusSelector

  defdelegate radius_selector_compact(assigns),
    to: EventasaurusWeb.Components.EventListing.RadiusSelector

  # Category filter components
  defdelegate category_checkboxes(assigns),
    to: EventasaurusWeb.Components.EventListing.CategoryFilters

  defdelegate category_tags(assigns),
    to: EventasaurusWeb.Components.EventListing.CategoryFilters

  defdelegate category_dropdown(assigns),
    to: EventasaurusWeb.Components.EventListing.CategoryFilters

  defdelegate category_pills(assigns),
    to: EventasaurusWeb.Components.EventListing.CategoryFilters
end
