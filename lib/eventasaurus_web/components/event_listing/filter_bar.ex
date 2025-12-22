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
end
