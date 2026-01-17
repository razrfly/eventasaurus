defmodule EventasaurusWeb.Components.Movies.ViewModeToggle do
  @moduledoc """
  Toggle component for switching between "By Venue" and "By Day" views
  on movie screenings pages.

  ## Props

  - `view_mode` - Current mode: `:by_venue` or `:by_day` (required)
  - `on_change` - Event name to send when mode changes (default: "change_view_mode")
  - `target` - Target for phx-click (optional, for LiveComponents)
  """

  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  attr :view_mode, :atom, required: true, values: [:by_venue, :by_day]
  attr :on_change, :string, default: "change_view_mode"
  attr :target, :any, default: nil

  def view_mode_toggle(assigns) do
    ~H"""
    <div class="flex items-center bg-gray-100 rounded-lg p-1 gap-1">
      <button
        type="button"
        phx-click={@on_change}
        phx-value-mode="by_venue"
        phx-target={@target}
        class={[
          "flex items-center px-4 py-2 rounded-md text-sm font-medium transition-all duration-200",
          if(@view_mode == :by_venue,
            do: "bg-white text-gray-900 shadow-sm",
            else: "text-gray-600 hover:text-gray-900 hover:bg-gray-50"
          )
        ]}
        aria-pressed={@view_mode == :by_venue}
      >
        <Heroicons.building_storefront class="w-4 h-4 mr-2" />
        <span><%= gettext("By Venue") %></span>
      </button>

      <button
        type="button"
        phx-click={@on_change}
        phx-value-mode="by_day"
        phx-target={@target}
        class={[
          "flex items-center px-4 py-2 rounded-md text-sm font-medium transition-all duration-200",
          if(@view_mode == :by_day,
            do: "bg-white text-gray-900 shadow-sm",
            else: "text-gray-600 hover:text-gray-900 hover:bg-gray-50"
          )
        ]}
        aria-pressed={@view_mode == :by_day}
      >
        <Heroicons.calendar_days class="w-4 h-4 mr-2" />
        <span><%= gettext("By Day") %></span>
      </button>
    </div>
    """
  end
end
