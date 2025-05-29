defmodule EventasaurusWeb.ThemeComponents do
  @moduledoc """
  Theme switching components for Eventasaurus.

  Provides components for host-only theme switching on event pages.
  """

  use Phoenix.Component

  @doc """
  Renders theme data for the root layout.

  This component sets up the necessary assigns for theme switching,
  including host detection and event information.
  """
  attr :event, :map, default: nil
  attr :current_user, :map, default: nil
  attr :theme, :string, default: "minimal"

  def theme_data(assigns) do
    ~H"""
    <!-- Theme data setup (no visual output) -->
    """
  end

  @doc """
  Determines if the current user is the host of the given event.
  """
  def is_event_host?(nil, _current_user), do: false
  def is_event_host?(_event, nil), do: false
  def is_event_host?(event, current_user) do
    event.user_id == current_user.id
  end

  @doc """
  Gets theme-related assigns for the layout.

  Returns a map with:
  - theme: the current theme name
  - is_event_host: boolean indicating if user can switch themes
  - event_id: the event ID for persistence
  """
  def get_theme_assigns(event, current_user) do
    %{
      theme: event && event.theme || "minimal",
      is_event_host: is_event_host?(event, current_user),
      event_id: event && event.id
    }
  end

  @doc """
  Renders a host-only theme preview badge.

  This shows hosts that they're viewing a themed event and can switch themes.
  """
  attr :theme, :string, required: true
  attr :is_host, :boolean, default: false
  attr :class, :string, default: ""

  def theme_badge(assigns) do
    ~H"""
    <%= if @is_host do %>
      <div class={["inline-flex items-center px-2 py-1 rounded-full text-xs font-medium",
                   "bg-blue-100 text-blue-800 border border-blue-200", @class]}>
        <div class="w-2 h-2 bg-blue-400 rounded-full mr-1"></div>
        Theme: <%= String.capitalize(@theme) %>
        <span class="ml-1 text-blue-600">(Host View)</span>
      </div>
    <% end %>
    """
  end

  @doc """
  Gets the available themes for selection.
  """
  def available_themes do
    [
      %{value: "minimal", label: "Minimal", description: "Clean and simple"},
      %{value: "cosmic", label: "Cosmic", description: "Dark space theme"},
      %{value: "velocity", label: "Velocity", description: "Fast and modern"},
      %{value: "celebration", label: "Celebration", description: "Bright and festive"},
      %{value: "nature", label: "Nature", description: "Earth tones and organic"},
      %{value: "professional", label: "Professional", description: "Corporate and clean"},
      %{value: "retro", label: "Retro", description: "Vintage and nostalgic"}
    ]
  end

  @doc """
  Renders theme selection options for forms.
  """
  attr :selected, :string, default: "minimal"
  attr :field, Phoenix.HTML.FormField, required: true

  def theme_select(assigns) do
    ~H"""
    <select
      field={@field}
      class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
    >
      <%= for theme <- available_themes() do %>
        <option
          value={theme.value}
          selected={@selected == theme.value}
        >
          <%= theme.label %> - <%= theme.description %>
        </option>
      <% end %>
    </select>
    """
  end
end
