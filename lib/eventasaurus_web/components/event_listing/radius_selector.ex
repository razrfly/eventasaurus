defmodule EventasaurusWeb.Components.EventListing.RadiusSelector do
  @moduledoc """
  Radius selector component for geographic event filtering.

  Provides a dropdown to select search radius in kilometers.
  Used by city pages and any location-based event search.

  ## Events Emitted

  - `change_radius` with `radius` value (integer km)

  ## Example

      <.radius_selector
        radius_km={@radius_km}
        default_radius={50}
        options={[5, 10, 25, 50, 100]}
      />

  Or within a form:

      <.radius_selector
        radius_km={@radius_km}
        name="filter[radius]"
        form_mode={true}
      />
  """

  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  @default_options [5, 10, 25, 50, 100]
  @default_radius 50

  @doc """
  Renders a radius selector dropdown.

  ## Attributes

  - `radius_km` - Currently selected radius in kilometers
  - `default_radius` - Default radius value (default: 50)
  - `options` - List of radius options in km (default: [5, 10, 25, 50, 100])
  - `name` - Input name attribute for form submission (default: "radius")
  - `form_mode` - If true, works within a form via phx-change on parent.
                  If false, emits `change_radius` event directly. (default: false)
  - `label` - Label text (default: "Search Radius")
  - `show_label` - Whether to show the label (default: true)
  - `class` - Additional CSS classes for the container
  """
  attr :radius_km, :integer, default: nil
  attr :default_radius, :integer, default: @default_radius
  attr :options, :list, default: @default_options
  attr :name, :string, default: "radius"
  attr :form_mode, :boolean, default: false
  attr :label, :string, default: nil
  attr :show_label, :boolean, default: true
  attr :class, :string, default: nil

  def radius_selector(assigns) do
    # Use default_radius if radius_km is nil
    assigns = assign_new(assigns, :current_radius, fn ->
      assigns.radius_km || assigns.default_radius
    end)

    # Default label with translation
    assigns = assign_new(assigns, :display_label, fn ->
      assigns.label || gettext("Search Radius")
    end)

    ~H"""
    <div class={["radius-selector", @class]}>
      <%= if @show_label do %>
        <label class="block text-sm font-medium text-gray-700 mb-2">
          <%= @display_label %>
        </label>
      <% end %>

      <%= if @form_mode do %>
        <select
          name={@name}
          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
        >
          <%= for km <- @options do %>
            <option value={km} selected={@current_radius == km}>
              <%= km %> km
            </option>
          <% end %>
        </select>
      <% else %>
        <select
          phx-change="change_radius"
          name={@name}
          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 cursor-pointer"
        >
          <%= for km <- @options do %>
            <option value={km} selected={@current_radius == km}>
              <%= km %> km
            </option>
          <% end %>
        </select>
      <% end %>
    </div>
    """
  end

  @doc """
  Compact inline radius selector for use in filter bars.

  Shows as a smaller dropdown without label, suitable for horizontal layouts.

  ## Attributes

  Same as `radius_selector/1` but defaults to `show_label: false`.
  """
  attr :radius_km, :integer, default: nil
  attr :default_radius, :integer, default: @default_radius
  attr :options, :list, default: @default_options
  attr :name, :string, default: "radius"
  attr :form_mode, :boolean, default: false
  attr :class, :string, default: nil

  def radius_selector_compact(assigns) do
    assigns = assign_new(assigns, :current_radius, fn ->
      assigns.radius_km || assigns.default_radius
    end)

    ~H"""
    <div class={["inline-flex items-center gap-2", @class]}>
      <span class="text-sm text-gray-600"><%= gettext("Radius:") %></span>
      <%= if @form_mode do %>
        <select
          name={@name}
          class="appearance-none bg-white border border-gray-300 rounded-lg px-3 py-1.5 pr-8 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
        >
          <%= for km <- @options do %>
            <option value={km} selected={@current_radius == km}>
              <%= km %> km
            </option>
          <% end %>
        </select>
      <% else %>
        <div class="relative inline-block">
          <select
            phx-change="change_radius"
            name={@name}
            class="appearance-none bg-white border border-gray-300 rounded-lg px-3 py-1.5 pr-8 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 cursor-pointer"
          >
            <%= for km <- @options do %>
              <option value={km} selected={@current_radius == km}>
                <%= km %> km
              </option>
            <% end %>
          </select>
          <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-gray-500">
            <Heroicons.chevron_down class="w-4 h-4" />
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
