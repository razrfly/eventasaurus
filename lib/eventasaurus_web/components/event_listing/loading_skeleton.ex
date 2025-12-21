defmodule EventasaurusWeb.Components.EventListing.LoadingSkeleton do
  @moduledoc """
  Loading skeleton component for event listings.

  Provides visual placeholders while events are being loaded.
  Uses CSS animations for a polished loading experience.

  ## Example

      <.loading_skeleton />
      <.loading_skeleton card_count={9} />
  """

  use Phoenix.Component

  @doc """
  Renders a loading skeleton for the event grid.

  ## Attributes

  - `card_count` - Number of skeleton cards to display (default: 6)
  - `message` - Loading message to display (default: "Loading events...")
  """
  attr :card_count, :integer, default: 6
  attr :message, :string, default: "Loading events..."

  def loading_skeleton(assigns) do
    ~H"""
    <div class="animate-pulse">
      <!-- Results count skeleton -->
      <div class="mb-4">
        <div class="h-4 w-32 bg-gray-200 rounded"></div>
      </div>

      <!-- Event cards skeleton grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for _i <- 1..@card_count do %>
          <.skeleton_card />
        <% end %>
      </div>

      <!-- Pagination skeleton -->
      <div class="mt-8 flex justify-center">
        <div class="flex items-center space-x-2">
          <div class="h-10 w-20 bg-gray-200 rounded"></div>
          <div class="h-10 w-10 bg-gray-300 rounded"></div>
          <div class="h-10 w-10 bg-gray-200 rounded"></div>
          <div class="h-10 w-10 bg-gray-200 rounded"></div>
          <div class="h-10 w-20 bg-gray-200 rounded"></div>
        </div>
      </div>

      <p class="text-center text-sm text-gray-500 mt-4">
        <%= @message %>
      </p>
    </div>
    """
  end

  @doc """
  Renders a single skeleton card placeholder.
  """
  def skeleton_card(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)

    ~H"""
    <div class={"bg-white rounded-lg shadow overflow-hidden #{@class}"}>
      <!-- Image placeholder -->
      <div class="h-48 bg-gray-200"></div>
      <!-- Content -->
      <div class="p-4 space-y-3">
        <!-- Title -->
        <div class="h-5 bg-gray-200 rounded w-3/4"></div>
        <!-- Date/time -->
        <div class="flex items-center space-x-2">
          <div class="h-4 w-4 bg-gray-300 rounded"></div>
          <div class="h-4 bg-gray-200 rounded w-1/2"></div>
        </div>
        <!-- Location -->
        <div class="flex items-center space-x-2">
          <div class="h-4 w-4 bg-gray-300 rounded"></div>
          <div class="h-4 bg-gray-200 rounded w-2/3"></div>
        </div>
        <!-- Category badge -->
        <div class="flex space-x-2">
          <div class="h-6 w-16 bg-gray-200 rounded-full"></div>
          <div class="h-6 w-20 bg-gray-200 rounded-full"></div>
        </div>
      </div>
    </div>
    """
  end
end
