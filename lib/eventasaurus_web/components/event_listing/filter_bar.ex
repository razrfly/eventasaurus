defmodule EventasaurusWeb.Components.EventListing.FilterBar do
  @moduledoc """
  Filter bar components for event listings.

  Provides quick date filters, search input, and sort controls.
  All components emit events to the parent LiveView.

  ## Events Emitted

  - `quick_date_filter` with `range` value (e.g., "today", "tomorrow", "next_7_days")
  - `clear_date_filter` - clears date filter
  - `search` with `search` value - search form submission

  ## Example

      <.filter_bar
        filters={@filters}
        active_date_range={@active_date_range}
        date_range_counts={@date_range_counts}
        all_events_count={@all_events_count}
      />
  """

  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  @doc """
  Renders the complete filter bar with search and quick date filters.

  ## Attributes

  - `filters` - Current filter values (map with :search key)
  - `active_date_range` - Currently active date range atom (nil for "all")
  - `date_range_counts` - Map of date range atoms to event counts
  - `all_events_count` - Total count for "All Events" button
  - `show_search` - Whether to show search input (default: true)
  - `show_date_filters` - Whether to show date filter buttons (default: true)
  """
  attr :filters, :map, required: true
  attr :active_date_range, :atom, default: nil
  attr :date_range_counts, :map, default: %{}
  attr :all_events_count, :integer, default: 0
  attr :show_search, :boolean, default: true
  attr :show_date_filters, :boolean, default: true

  def filter_bar(assigns) do
    ~H"""
    <div class="space-y-4">
      <.search_bar :if={@show_search} filters={@filters} />

      <.quick_date_filters
        :if={@show_date_filters}
        active_date_range={@active_date_range}
        date_range_counts={@date_range_counts}
        all_events_count={@all_events_count}
      />
    </div>
    """
  end

  @doc """
  Renders the search input form.

  Emits `search` event on form submit.
  """
  attr :filters, :map, required: true
  attr :placeholder, :string, default: "Search events..."

  def search_bar(assigns) do
    ~H"""
    <form phx-submit="search" class="relative">
      <input
        type="text"
        name="search"
        value={@filters[:search]}
        placeholder={@placeholder}
        class="w-full px-4 py-3 pr-12 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
      />
      <button type="submit" class="absolute right-3 top-3.5">
        <Heroicons.magnifying_glass class="w-5 h-5 text-gray-500" />
      </button>
    </form>
    """
  end

  @doc """
  Renders quick date filter buttons.

  Each button emits `quick_date_filter` event with `range` value.
  Shows event counts for each date range.
  """
  attr :active_date_range, :atom, default: nil
  attr :date_range_counts, :map, default: %{}
  attr :all_events_count, :integer, default: 0

  def quick_date_filters(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-2">
        <h2 class="text-sm font-medium text-gray-700">
          <%= gettext("Quick date filters") %>
        </h2>
        <%= if @active_date_range do %>
          <button
            phx-click="clear_date_filter"
            class="text-sm text-blue-600 hover:text-blue-800 flex items-center"
          >
            <Heroicons.x_mark class="w-4 h-4 mr-1" />
            <%= gettext("Clear date filter") %>
          </button>
        <% end %>
      </div>
      <div class="flex flex-wrap gap-2">
        <.date_filter_button
          range={:all}
          label={gettext("All Events")}
          active={@active_date_range == nil}
          count={@all_events_count}
        />
        <.date_filter_button
          range={:today}
          label={gettext("Today")}
          active={@active_date_range == :today}
          count={Map.get(@date_range_counts, :today, 0)}
        />
        <.date_filter_button
          range={:tomorrow}
          label={gettext("Tomorrow")}
          active={@active_date_range == :tomorrow}
          count={Map.get(@date_range_counts, :tomorrow, 0)}
        />
        <.date_filter_button
          range={:this_weekend}
          label={gettext("This Weekend")}
          active={@active_date_range == :this_weekend}
          count={Map.get(@date_range_counts, :this_weekend, 0)}
        />
        <.date_filter_button
          range={:next_7_days}
          label={gettext("Next 7 Days")}
          active={@active_date_range == :next_7_days}
          count={Map.get(@date_range_counts, :next_7_days, 0)}
        />
        <.date_filter_button
          range={:next_30_days}
          label={gettext("Next 30 Days")}
          active={@active_date_range == :next_30_days}
          count={Map.get(@date_range_counts, :next_30_days, 0)}
        />
        <.date_filter_button
          range={:this_month}
          label={gettext("This Month")}
          active={@active_date_range == :this_month}
          count={Map.get(@date_range_counts, :this_month, 0)}
        />
        <.date_filter_button
          range={:next_month}
          label={gettext("Next Month")}
          active={@active_date_range == :next_month}
          count={Map.get(@date_range_counts, :next_month, 0)}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders sort controls dropdown.

  Emits `sort` event with `sort_by` value.

  ## Attributes

  - `sort_by` - Currently active sort field (:starts_at, :distance, :title)
  - `show_distance` - Whether to show distance option. Only enable when events
    have a `:distance` field populated (e.g., location-based search results).
    Requires backend support in EventPagination.sort_events/2.
  """
  attr :sort_by, :atom, default: :starts_at
  attr :show_distance, :boolean, default: false

  def sort_controls(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-sm text-gray-600"><%= gettext("Sort by:") %></span>
      <div class="relative inline-block">
        <form phx-change="sort" class="inline-block">
          <select
            name="sort_by"
            class="appearance-none bg-white border border-gray-300 rounded-lg px-3 py-1.5 pr-8 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 cursor-pointer"
          >
            <option value="starts_at" selected={@sort_by == :starts_at}>
              <%= gettext("Date") %>
            </option>
            <%= if @show_distance do %>
              <option value="distance" selected={@sort_by == :distance}>
                <%= gettext("Distance") %>
              </option>
            <% end %>
            <option value="title" selected={@sort_by == :title}>
              <%= gettext("Title") %>
            </option>
          </select>
          <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-gray-500">
            <Heroicons.chevron_down class="w-4 h-4" />
          </div>
        </form>
      </div>
    </div>
    """
  end

  @doc """
  Individual date filter button.

  Emits `quick_date_filter` event with `range` value.
  """
  attr :range, :atom, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :count, :integer, default: 0

  def date_filter_button(assigns) do
    ~H"""
    <button
      phx-click="quick_date_filter"
      phx-value-range={@range}
      class={[
        "px-3 py-2 rounded-lg font-medium text-sm transition-all",
        if(@active,
          do: "bg-blue-600 text-white shadow-md",
          else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
        )
      ]}
    >
      <%= @label %>
      <%= if @count > 0 do %>
        <span class={[
          "ml-1.5 px-1.5 py-0.5 rounded-full text-xs",
          if(@active, do: "bg-blue-700", else: "bg-gray-200 text-gray-600")
        ]}>
          <%= @count %>
        </span>
      <% end %>
    </button>
    """
  end

  @doc """
  Renders a grid/list view toggle.

  Emits `change_view` event with `view` value ("grid" or "list").

  ## Attributes

  - `view_mode` - Currently active view mode ("grid" or "list")
  """
  attr :view_mode, :string, default: "grid"

  def view_toggle(assigns) do
    ~H"""
    <div class="flex bg-gray-100 rounded-lg p-1">
      <button
        phx-click="change_view"
        phx-value-view="grid"
        class={[
          "px-3 py-1.5 rounded transition-all",
          if(@view_mode == "grid", do: "bg-white shadow-sm", else: "hover:bg-gray-200")
        ]}
        title={gettext("Grid view")}
      >
        <Heroicons.squares_2x2 class="w-5 h-5" />
      </button>
      <button
        phx-click="change_view"
        phx-value-view="list"
        class={[
          "px-3 py-1.5 rounded transition-all",
          if(@view_mode == "list", do: "bg-white shadow-sm", else: "hover:bg-gray-200")
        ]}
        title={gettext("List view")}
      >
        <Heroicons.list_bullet class="w-5 h-5" />
      </button>
    </div>
    """
  end

  @doc """
  Renders simple active filter tags with remove buttons for entity pages.

  Shows currently active filters (search, date range, sort) as removable badges.
  Emits events to clear individual filters. Used by venue and performer pages.

  For city pages with more filter options (radius, categories), use
  `EventasaurusWeb.EventComponents.active_filter_tags/1` instead.

  ## Attributes

  - `filters` - Current filter values (map with :search key)
  - `active_date_range` - Currently active date range atom (nil for none)
  - `sort_by` - Currently active sort field (:starts_at, :title, :distance)

  ## Events Emitted

  - `clear_search` - Clear the search filter
  - `clear_date_filter` - Clear the date range filter
  - `sort` with sort_by="starts_at" - Reset sort to default
  """
  attr :filters, :map, default: %{}
  attr :active_date_range, :atom, default: nil
  attr :sort_by, :atom, default: :starts_at

  def simple_filter_tags(assigns) do
    # Check if any filters are active
    has_search = assigns.filters[:search] && assigns.filters[:search] != ""
    has_date_range = assigns.active_date_range != nil
    has_non_default_sort = assigns.sort_by != :starts_at

    assigns =
      assigns
      |> assign(:has_search, has_search)
      |> assign(:has_date_range, has_date_range)
      |> assign(:has_non_default_sort, has_non_default_sort)
      |> assign(:has_any_filter, has_search || has_date_range || has_non_default_sort)

    ~H"""
    <div :if={@has_any_filter} class="flex flex-wrap gap-2">
      <%= if @has_search do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          <%= gettext("Search:") %> <%= @filters[:search] %>
          <button phx-click="clear_search" class="ml-2 hover:text-blue-600" title={gettext("Clear search")}>
            <Heroicons.x_mark class="w-4 h-4" />
          </button>
        </span>
      <% end %>

      <%= if @has_date_range do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          <%= date_range_label(@active_date_range) %>
          <button phx-click="clear_date_filter" class="ml-2 hover:text-blue-600" title={gettext("Clear date filter")}>
            <Heroicons.x_mark class="w-4 h-4" />
          </button>
        </span>
      <% end %>

      <%= if @has_non_default_sort do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          <%= gettext("Sorted by:") %> <%= sort_label(@sort_by) %>
          <button phx-click="sort" phx-value-sort_by="starts_at" class="ml-2 hover:text-blue-600" title={gettext("Reset sort")}>
            <Heroicons.x_mark class="w-4 h-4" />
          </button>
        </span>
      <% end %>
    </div>
    """
  end

  # Helper to get human-readable date range label
  defp date_range_label(:today), do: gettext("Today")
  defp date_range_label(:tomorrow), do: gettext("Tomorrow")
  defp date_range_label(:this_weekend), do: gettext("This Weekend")
  defp date_range_label(:next_7_days), do: gettext("Next 7 Days")
  defp date_range_label(:next_30_days), do: gettext("Next 30 Days")
  defp date_range_label(:this_month), do: gettext("This Month")
  defp date_range_label(:next_month), do: gettext("Next Month")
  defp date_range_label(_), do: gettext("Date Filter")

  # Helper to get human-readable sort label
  defp sort_label(:title), do: gettext("Title")
  defp sort_label(:distance), do: gettext("Distance")
  defp sort_label(_), do: gettext("Date")
end
