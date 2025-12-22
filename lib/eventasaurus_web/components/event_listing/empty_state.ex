defmodule EventasaurusWeb.Components.EventListing.EmptyState do
  @moduledoc """
  Empty state component for event listings.

  Displays a friendly message when no events are found,
  with optional suggestions for adjusting filters.

  ## Example

      <.empty_state />
      <.empty_state
        title="No events at this venue"
        message="Check back later for upcoming events"
      />
  """

  use Phoenix.Component

  @doc """
  Renders an empty state message.

  ## Attributes

  - `title` - Main heading (default: "No events found")
  - `message` - Subtext message (default: "Try adjusting your filters or search query")
  - `show_icon` - Whether to show the icon (default: true)
  """
  attr :title, :string, default: "No events found"
  attr :message, :string, default: "Try adjusting your filters or search query"
  attr :show_icon, :boolean, default: true

  def empty_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <Heroicons.calendar_days :if={@show_icon} class="mx-auto h-12 w-12 text-gray-400" />
      <h3 class="mt-2 text-lg font-medium text-gray-900">
        <%= @title %>
      </h3>
      <p class="mt-1 text-sm text-gray-500">
        <%= @message %>
      </p>
    </div>
    """
  end
end
