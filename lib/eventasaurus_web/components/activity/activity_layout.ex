defmodule EventasaurusWeb.Components.Activity.ActivityLayout do
  @moduledoc """
  Two-column responsive layout for activity pages.

  Provides a consistent container structure with:
  - Main content area (2/3 width on large screens)
  - Sidebar area (1/3 width on large screens)
  - Single column stack on mobile

  ## Example

      <ActivityLayout.activity_layout>
        <:main>
          <MovieHeroCard ... />
          <ShowtimesSection ... />
        </:main>
        <:sidebar>
          <VenueLocationCard ... />
          <PlanWithFriendsCard ... />
          <SourceAttributionCard ... />
        </:sidebar>
      </ActivityLayout.activity_layout>
  """
  use Phoenix.Component

  @doc """
  Renders a two-column layout with main content and sidebar.

  ## Slots

    * `:main` - Required. The main content area (hero, showtimes, details).
    * `:sidebar` - Required. The sidebar area (map, actions, sources).

  ## Attributes

    * `:class` - Optional. Additional CSS classes for the outer container.
    * `:main_class` - Optional. Additional CSS classes for the main column.
    * `:sidebar_class` - Optional. Additional CSS classes for the sidebar column.
    * `:gap` - Optional. Gap size between columns. Defaults to "8" (gap-8).
  """
  attr :class, :string, default: ""
  attr :main_class, :string, default: ""
  attr :sidebar_class, :string, default: ""
  attr :gap, :string, default: "8"

  slot :main, required: true
  slot :sidebar, required: true

  def activity_layout(assigns) do
    ~H"""
    <div class={[
      "grid grid-cols-1 lg:grid-cols-3",
      gap_class(@gap),
      @class
    ]}>
      <%!-- Main Content Column (2/3 width on large screens) --%>
      <div class={["lg:col-span-2 space-y-8", @main_class]}>
        <%= render_slot(@main) %>
      </div>

      <%!-- Sidebar Column (1/3 width on large screens) --%>
      <div class={["space-y-6", @sidebar_class]}>
        <%= render_slot(@sidebar) %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a full-width section that spans both columns.

  Useful for content that should break out of the two-column layout,
  such as related events or full-width media galleries.

  ## Attributes

    * `:class` - Optional. Additional CSS classes for the section.
  """
  attr :class, :string, default: ""

  slot :inner_block, required: true

  def full_width_section(assigns) do
    ~H"""
    <div class={["lg:col-span-3", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  # Private helpers

  defp gap_class("4"), do: "gap-4"
  defp gap_class("6"), do: "gap-6"
  defp gap_class("8"), do: "gap-8"
  defp gap_class("10"), do: "gap-10"
  defp gap_class("12"), do: "gap-12"
  defp gap_class(_), do: "gap-8"
end
