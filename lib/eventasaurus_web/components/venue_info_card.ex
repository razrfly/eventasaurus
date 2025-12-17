defmodule EventasaurusWeb.Components.VenueInfoCard do
  @moduledoc """
  Reusable component for displaying venue information in event detail pages.

  Displays venue name with link, address, and optional icon. Used in the
  activity/event show page's key details grid.
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext
  use Phoenix.VerifiedRoutes, endpoint: EventasaurusWeb.Endpoint, router: EventasaurusWeb.Router

  @doc """
  Renders a venue information card with name, link, and address.

  ## Examples

      <VenueInfoCard.venue_info_card venue={@event.venue} />
      <VenueInfoCard.venue_info_card venue={@event.venue} show_icon={false} />

  ## Attributes

    * `:venue` - Required. The venue map with `:name`, `:slug`, and optional `:address`.
    * `:show_icon` - Optional. Whether to show the map pin icon. Defaults to `true`.
    * `:class` - Optional. Additional CSS classes for the container.
  """
  attr :venue, :map, required: true
  attr :show_icon, :boolean, default: true
  attr :class, :string, default: ""

  def venue_info_card(assigns) do
    ~H"""
    <div class={@class}>
      <div class="flex items-center text-gray-600 mb-1">
        <%= if @show_icon do %>
          <Heroicons.map_pin class="w-5 h-5 mr-2" />
        <% end %>
        <span class="font-medium"><%= gettext("Venue") %></span>
      </div>
      <p class="text-gray-900">
        <.link
          navigate={~p"/venues/#{@venue.slug}"}
          class="font-semibold hover:text-indigo-600 transition-colors"
        >
          <%= @venue.name %>
        </.link>
        <%= if @venue.address do %>
          <br />
          <span class="text-sm text-gray-600">
            <%= @venue.address %>
          </span>
        <% end %>
      </p>
    </div>
    """
  end

  @doc """
  Renders a compact venue display with just name and optional address.

  Useful for contexts where the full card is too large.

  ## Examples

      <VenueInfoCard.venue_compact venue={@event.venue} />
  """
  attr :venue, :map, required: true
  attr :link, :boolean, default: true
  attr :class, :string, default: ""

  def venue_compact(assigns) do
    ~H"""
    <div class={["text-gray-600", @class]}>
      <%= if @link do %>
        <.link
          navigate={~p"/venues/#{@venue.slug}"}
          class="font-medium hover:text-indigo-600 transition-colors"
        >
          <%= @venue.name %>
        </.link>
      <% else %>
        <span class="font-medium"><%= @venue.name %></span>
      <% end %>
      <%= if @venue.address do %>
        <span class="text-sm text-gray-500 ml-1">• <%= @venue.address %></span>
      <% end %>
    </div>
    """
  end
end
