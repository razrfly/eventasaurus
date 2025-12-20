defmodule EventasaurusWeb.Components.Activity.HeroCardBadge do
  @moduledoc """
  Reusable badge component for hero cards.

  Provides consistent styling for category badges, status indicators,
  and other tag-like elements across all hero card components.

  ## Features

  - Consistent rounded pill styling
  - Theme-aware color schemes using HeroCardTheme
  - Optional icon support via HeroCardIcons
  - Flexible content via slots

  ## Usage

      alias EventasaurusWeb.Components.Activity.HeroCardBadge

      # Simple themed badge
      <HeroCardBadge.badge theme={:music}>Music</HeroCardBadge.badge>

      # Badge with icon
      <HeroCardBadge.badge theme={:trivia} icon={:trivia}>Pub Quiz</HeroCardBadge.badge>

      # Custom color badge
      <HeroCardBadge.badge color="bg-green-500/20 text-green-100">
        <Heroicons.check class="w-4 h-4 mr-1.5" />
        Verified
      </HeroCardBadge.badge>
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias EventasaurusWeb.Components.Activity.{HeroCardIcons, HeroCardTheme}

  @doc """
  Renders a styled badge for hero cards.

  ## Attributes

    * `:theme` - Optional. Theme atom for automatic styling (e.g., :music, :trivia).
    * `:color` - Optional. Custom color classes (overrides theme).
    * `:icon` - Optional. Icon type to render before content.
    * `:class` - Optional. Additional CSS classes.

  ## Slots

    * `:inner_block` - Required. Badge content.
  """
  attr :theme, :atom, default: nil, doc: "Theme for automatic styling"
  attr :color, :string, default: nil, doc: "Custom color classes"
  attr :icon, :any, default: nil, doc: "Icon type (atom or string)"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  slot :inner_block, required: true

  def badge(assigns) do
    color_class = get_color_class(assigns.theme, assigns.color)
    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <span class={[
      "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
      @color_class,
      @class
    ]}>
      <%= if @icon do %>
        <HeroCardIcons.icon type={@icon} class="w-4 h-4 mr-1.5" />
      <% end %>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  @doc """
  Renders a multi-city badge (common pattern).
  """
  attr :class, :string, default: ""

  def multi_city_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
      "bg-blue-500/20 text-blue-100",
      @class
    ]}>
      <Heroicons.map_pin class="w-4 h-4 mr-1.5" />
      <%= gettext("Multi-city") %>
    </span>
    """
  end

  @doc """
  Renders a verified/active badge (common pattern).
  """
  attr :label, :string, default: nil
  attr :class, :string, default: ""

  def verified_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
      "bg-green-500/20 text-green-100",
      @class
    ]}>
      <Heroicons.check_badge class="w-4 h-4 mr-1.5" />
      <%= @label || gettext("Verified") %>
    </span>
    """
  end

  @doc """
  Renders a success/positive badge (green).

  Used for positive indicators like "Free Entry", "X upcoming events", etc.
  """
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def success_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
      "bg-green-500/20 text-green-100",
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  @doc """
  Renders a secondary/muted badge.
  """
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def muted_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
      "bg-white/10 text-white/80",
      @class
    ]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  # Helper to determine color class
  defp get_color_class(nil, nil), do: "bg-white/20 text-white"
  defp get_color_class(_theme, color) when is_binary(color), do: color
  defp get_color_class(theme, nil), do: HeroCardTheme.badge_class(theme)
end
