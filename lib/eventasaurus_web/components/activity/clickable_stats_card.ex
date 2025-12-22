defmodule EventasaurusWeb.Components.Activity.ClickableStatsCard do
  @moduledoc """
  A sidebar stats card with clickable stat items that act as filters.

  Used on performer, venue, and other entity pages to show event counts
  that can be clicked to filter the event list.

  ## Example

      <ClickableStatsCard.clickable_stats_card
        title={gettext("Artist Stats")}
        active_filter={@time_filter}
      >
        <:stat
          label={gettext("Upcoming Events")}
          count={@upcoming_count}
          filter_value={:upcoming}
          active={@time_filter == :upcoming}
        />
        <:stat
          label={gettext("Past Events")}
          count={@past_count}
          filter_value={:past}
          active={@time_filter == :past}
        />
        <:stat
          label={gettext("All Events")}
          count={@all_count}
          filter_value={:all}
          active={@time_filter == :all}
        />
      </ClickableStatsCard.clickable_stats_card>
  """

  use Phoenix.Component

  @doc """
  Renders a clickable stats card for the sidebar.

  ## Attributes

  - `title` - Card header title
  - `active_filter` - Currently active filter value (for highlighting)

  ## Slots

  - `stat` - Individual stat items with label, count, filter_value, and active flag
  """
  attr :title, :string, required: true
  attr :active_filter, :atom, default: nil

  slot :stat, required: true do
    attr :label, :string, required: true
    attr :count, :integer, required: true
    attr :filter_value, :atom, required: true
    attr :active, :boolean
  end

  def clickable_stats_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-md p-6">
      <h3 class="text-lg font-semibold text-gray-900 mb-4">
        <%= @title %>
      </h3>
      <div class="space-y-2">
        <%= for stat <- @stat do %>
          <.stat_item
            label={stat.label}
            count={stat.count}
            filter_value={stat.filter_value}
            active={stat[:active] || false}
          />
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders an individual clickable stat item.

  Clicking the stat emits a "time_filter" event with the filter_value.
  """
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :filter_value, :atom, required: true
  attr :active, :boolean, default: false

  def stat_item(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="time_filter"
      phx-value-filter={@filter_value}
      class={[
        "w-full flex justify-between items-center px-3 py-2 rounded-lg transition-colors",
        "hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2",
        @active && "bg-indigo-50 text-indigo-700",
        !@active && "text-gray-600"
      ]}
    >
      <span class={[@active && "font-medium"]}>
        <%= @label %>
      </span>
      <span class={[
        "font-semibold px-2 py-0.5 rounded-full text-sm",
        @active && "bg-indigo-100 text-indigo-800",
        !@active && "bg-gray-100 text-gray-900"
      ]}>
        <%= @count %>
      </span>
    </button>
    """
  end
end
